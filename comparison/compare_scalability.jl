"""
    compare_scalability.jl

Scalability analysis (Task 5) for CHARM.

A large dataset is sampled into nested sub-databases holding 10%, 25%, 50%,
75% and 100% of its transactions.  Every implementation is run on each
sub-database with the same *relative* minimum support, so the absolute
`minsup` scales with the database size, as in the usual scalability protocol.

  * basic     : Julia implementation without the optimization
  * optimized : Julia implementation with BitVector/SIMD (`mine_file_bit`)
  * spmf      : SPMF `Charm_bitset` reference

Each run is a separate OS process.  Wall-clock time includes the fixed start-up
cost of Julia or the JVM, which would distort the growth analysis, so the
script measures that cost once per implementation on a tiny dataset and
reports `net_seconds = wall_seconds - baseline_seconds`.  The growth analysis
(linear / polynomial / exponential) is fitted on `net_seconds`.

Run from the repository root:

    julia --project=. comparison/compare_scalability.jl

Environment variables (all optional):

    SCALABILITY_DATASET  dataset name              (default T10I4D100K)
    SCALABILITY_RATIO    relative minsup, e.g. 0.01 (default depends on dataset)
    SCALABILITY_SEED     RNG seed for the sampling (default 42)
    SCALABILITY_RUNS     repetitions per point     (default 3)
    MEMORY_LIMIT_MB      kill a run above this RSS (default 6000)
    SPMF_JAR             path to spmf.jar          (default tools/spmf.jar)
    SPMF_JAVA_OPTS       extra JVM flags, e.g. "-Xmx2g"
    SCALABILITY_RESULTS  detailed CSV   (default comparison/metrics/scalability_result.csv)
    SCALABILITY_SUMMARY  summary CSV    (default comparison/metrics/scalability_summary.csv)
    SCALABILITY_ANALYSIS growth CSV     (default comparison/metrics/scalability_analysis.csv)
"""

using Random

include(joinpath(@__DIR__, "common.jl"))

const FRACTIONS = [0.10, 0.25, 0.50, 0.75, 1.00]

const DATASET = get(ENV, "SCALABILITY_DATASET", "T10I4D100K")
const DEFAULT_RATIOS = Dict("T10I4D100K" => 0.01, "retail" => 0.01, "accidents" => 0.6,
                            "chess" => 0.7, "mushrooms" => 0.3)
const RATIO = parse(Float64, get(ENV, "SCALABILITY_RATIO",
                                 string(get(DEFAULT_RATIOS, DATASET, 0.05))))
const SEED = parse(Int, get(ENV, "SCALABILITY_SEED", "42"))
const RUNS = parse(Int, get(ENV, "SCALABILITY_RUNS", "3"))

"One monitored run. Returns (seconds, peak_mb, itemsets); seconds is NaN if the run was killed."
function measure(impl, input, minsup, ratio, jar)
    output = tempname() * ".txt"
    command = build_command(impl, input, minsup, ratio, output, jar)
    seconds, peak_mb, exceeded, ok = run_monitored(command)
    if exceeded
        rm(output; force = true)
        @warn "Memory limit exceeded; run discarded" impl input minsup limit_mb = MAX_MEMORY_MB
        return NaN, peak_mb, -1
    end
    if !ok || !isfile(output)
        error("Run failed for $impl on $input (minsup=$minsup)\ncommand: $command")
    end
    itemsets = count_itemsets(output)
    rm(output; force = true)
    return seconds, peak_mb, itemsets
end
 
# --------------------------------------------------------------------------
# Sub-database creation
# --------------------------------------------------------------------------
 
"Transaction lines of an SPMF file (comment/metadata lines and blanks removed)."
function read_transaction_lines(path)
    lines = String[]
    for line in eachline(path)
        stripped = strip(line)
        isempty(stripped) && continue
        first(stripped) in ('#', '%', '@') && continue
        push!(lines, String(stripped))
    end
    return lines
end
 
"""
Write nested random sub-databases.  One shuffle is drawn once, and the k% subset
is the first k% of that shuffle, so each smaller subset is contained in every
larger one.  Returns [(fraction, path, transaction_count), ...].
"""
function write_subsets(lines, dir)
    n = length(lines)
    order = shuffle(MersenneTwister(SEED), collect(1:n))
    subsets = Tuple{Float64,String,Int}[]
    for fraction in FRACTIONS
        count = clamp(round(Int, fraction * n), 1, n)
        selected = sort(order[1:count])          # keep original relative order
        path = joinpath(dir, @sprintf("subset_%03d.txt", round(Int, fraction * 100)))
        open(path, "w") do io
            for i in selected
                println(io, lines[i])
            end
        end
        push!(subsets, (fraction, path, count))
    end
    return subsets
end
 
# --------------------------------------------------------------------------
# Growth analysis
# --------------------------------------------------------------------------
 
"Least squares y = intercept + slope * x. Returns (slope, intercept, r2)."
function linreg(x, y)
    mx, my = mean(x), mean(y)
    sxx = sum((x .- mx) .^ 2)
    sxx == 0 && return (0.0, my, 0.0)
    slope = sum((x .- mx) .* (y .- my)) / sxx
    intercept = my - slope * mx
    ss_tot = sum((y .- my) .^ 2)
    ss_res = sum((y .- (intercept .+ slope .* x)) .^ 2)
    return (slope, intercept, ss_tot == 0 ? 1.0 : 1 - ss_res / ss_tot)
end
 
"""
Fit three models to (database size n, runtime t):
 
  linear       t = a + b n        (R2 in raw space)
  power law    t = a n^b          (log-log fit, exponent b)
  exponential  t = a e^(c n)      (semi-log fit)
 
The power-law and exponential R2 are both measured on log(t), so they are
directly comparable.  Returns a NamedTuple with the fits and a verdict.
"""
function analyze_growth(n, t)
    t = max.(t, 1.0e-3)                  # guard against log(0) for very fast runs
    _, _, r2_linear = linreg(Float64.(n), t)
    exponent, _, r2_power = linreg(log.(n), log.(t))
    _, _, r2_exp = linreg(Float64.(n), log.(t))
 
    verdict = if 0.85 <= exponent <= 1.15 && r2_linear >= 0.98
        "linear"
    elseif r2_exp > r2_power + 0.01
        "possibly exponential"
    elseif exponent > 1.15
        "polynomial (about O(n^$(round(exponent; digits = 2))))"
    elseif exponent < 0.85
        "sub-linear (about O(n^$(round(exponent; digits = 2))))"
    else
        "near-linear"
    end
    return (exponent = exponent, r2_linear = r2_linear, r2_power = r2_power,
            r2_exp = r2_exp, verdict = verdict)
end
 
# --------------------------------------------------------------------------
# Benchmark
# --------------------------------------------------------------------------
 
"Fixed start-up cost (wall seconds) of each implementation on a tiny dataset."
function measure_baselines(impls, jar)
    toy = dataset_path("contextPasquier99")
    toy === nothing && error("Baseline dataset contextPasquier99.txt not found in data/toy/")
    ratio = 0.4
    minsup = max(1, ceil(Int, length(load_transactions(toy)) * ratio))
    baselines = Dict{String,Float64}()
    for impl in impls
        times = filter(!isnan, [measure(impl, toy, minsup, ratio, jar)[1] for _ in 1:RUNS])
        baselines[impl] = isempty(times) ? 0.0 : median(times)
        @info "Baseline" impl seconds = round(baselines[impl]; digits = 3)
    end
    return baselines
end

function main()
    jar = check_environment()

    source = dataset_path(DATASET)
    source === nothing && error("Dataset $DATASET not found in data/ or data/benchmark/")

    impls = IMPLEMENTATIONS

    results_path = get(ENV, "SCALABILITY_RESULTS", joinpath(@__DIR__, "metrics/scalability_result.csv"))
    summary_path = get(ENV, "SCALABILITY_SUMMARY", joinpath(@__DIR__, "metrics/scalability_summary.csv"))
    analysis_path = get(ENV, "SCALABILITY_ANALYSIS", joinpath(@__DIR__, "metrics/scalability_analysis.csv"))
    mkpath(dirname(abspath(results_path)))

    lines = read_transaction_lines(source)
    @info "Dataset" DATASET transactions = length(lines) minsup_ratio = RATIO seed = SEED runs = RUNS

    baselines = measure_baselines(impls, jar)

    summary = NamedTuple[]
    mktempdir() do dir
        subsets = write_subsets(lines, dir)
        open(results_path, "w") do io
            println(io, "dataset,implementation,fraction,transactions,minsup_ratio,minsup_count,run,wall_seconds,baseline_seconds,net_seconds,peak_mb,itemsets")
            for (fraction, path, count) in subsets
                minsup = max(1, ceil(Int, count * RATIO))
                @info "Sub-database" percent = round(Int, fraction * 100) transactions = count minsup
                for impl in impls
                    walls = Float64[]; peaks = Float64[]; itemsets = -1
                    for run_id in 1:RUNS
                        wall, peak, found = measure(impl, path, minsup, RATIO, jar)
                        isnan(wall) && continue
                        net = max(0.0, wall - baselines[impl])
                        push!(walls, wall); push!(peaks, peak); itemsets = found
                        println(io, join([
                            csv_field(DATASET), impl, @sprintf("%.2f", fraction), count,
                            @sprintf("%.6f", RATIO), minsup, run_id,
                            @sprintf("%.6f", wall), @sprintf("%.6f", baselines[impl]),
                            @sprintf("%.6f", net), @sprintf("%.2f", peak), found,
                        ], ","))
                        flush(io)
                    end
                    isempty(walls) && continue
                    wall = median(walls)
                    push!(summary, (
                        impl = impl, fraction = fraction, transactions = count,
                        minsup = minsup, wall = wall, baseline = baselines[impl],
                        net = max(0.0, wall - baselines[impl]),
                        peak = median(peaks), itemsets = itemsets,
                    ))
                    @info "Measured" impl wall_seconds = round(wall; digits = 3) itemsets
                end
            end
        end
    end

    write_summary(summary_path, summary)
    write_analysis(analysis_path, summary, impls)
    @info "Scalability results written" results_path summary_path analysis_path
end

function write_summary(path, summary)
    open(path, "w") do io
        println(io, "dataset,implementation,fraction,transactions,minsup_ratio,minsup_count,median_wall_seconds,baseline_seconds,net_seconds,median_peak_mb,itemsets")
        for row in summary
            println(io, join([
                csv_field(DATASET), row.impl, @sprintf("%.2f", row.fraction), row.transactions,
                @sprintf("%.6f", RATIO), row.minsup, @sprintf("%.6f", row.wall),
                @sprintf("%.6f", row.baseline), @sprintf("%.6f", row.net),
                @sprintf("%.2f", row.peak), row.itemsets,
            ], ","))
        end
    end
end

function write_analysis(path, summary, impls)
    println()
    @printf("%-10s %9s %9s %9s %9s %13s  %s\n", "impl", "exponent", "R2 lin", "R2 pow", "R2 exp", "t(100)/t(50)", "verdict")
    open(path, "w") do io
        println(io, "dataset,implementation,power_exponent,r2_linear,r2_power,r2_exponential,time_ratio_100_vs_50,verdict")
        for impl in impls
            rows = filter(row -> row.impl == impl, summary)
            length(rows) >= 3 || continue
            n = [row.transactions for row in rows]
            t = [row.net for row in rows]
            fit = analyze_growth(n, t)
            half = findfirst(row -> row.fraction == 0.5, rows)
            full = findfirst(row -> row.fraction == 1.0, rows)
            ratio = (half === nothing || full === nothing) ? NaN :
                    max(rows[full].net, 1.0e-3) / max(rows[half].net, 1.0e-3)
            @printf("%-10s %9.2f %9.3f %9.3f %9.3f %13.2f  %s\n", impl, fit.exponent,
                    fit.r2_linear, fit.r2_power, fit.r2_exp, ratio, fit.verdict)
            println(io, join([
                csv_field(DATASET), impl, @sprintf("%.4f", fit.exponent),
                @sprintf("%.4f", fit.r2_linear), @sprintf("%.4f", fit.r2_power),
                @sprintf("%.4f", fit.r2_exp), @sprintf("%.3f", ratio), csv_field(fit.verdict),
            ], ","))
        end
    end
    println()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
