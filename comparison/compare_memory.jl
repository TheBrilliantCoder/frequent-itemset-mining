"""
    compare_memory.jl

Peak-memory evaluation (Task 4) for CHARM:

  * basic     : Julia implementation without the optimization
  * optimized : Julia implementation with BitVector/SIMD (`mine_file_bit`)
  * spmf      : SPMF `Charm_bitset` reference

Every implementation runs in its own OS process.  Peak resident memory is read
from `VmHWM` in /proc/<pid>/status (the kernel's high-water mark of RSS).
Because Julia and the JVM both have a large fixed start-up footprint, the
script also measures a baseline run on a tiny dataset and reports
`net_mb = peak_mb - baseline_mb`.

Run from the repository root:

    julia --project=. comparison/compare_memory.jl

Environment variables (all optional):

    SPMF_JAR          path to spmf.jar              (default tools/spmf.jar)
    SPMF_JAVA_OPTS    extra JVM flags, e.g. "-Xmx2g"
    MEMORY_RUNS       repetitions per point         (default 3)
    MEMORY_LIMIT_MB   kill a run above this RSS     (default 6000)
    MEMORY_RESULTS    detailed CSV path             (default comparison/metrics/memory_result.csv)
    MEMORY_SUMMARY    summary CSV path              (default comparison/metrics/memory_summary.csv)
"""

include(joinpath(@__DIR__, "common.jl"))

# One "median" support ratio per dataset: the middle of the range used in
# compare_time.jl for the dataset's density class.
const MEMORY_RATIOS = Dict(
    "chess"      => 0.65,
    "mushrooms"  => 0.35,
    "accidents"  => 0.65,
    "retail"     => 0.04,
    "T10I4D100K" => 0.04,
)
const RUNS = parse(Int, get(ENV, "MEMORY_RUNS", "3"))

"One monitored run. Returns (peak_mb, seconds, itemsets)."
function measure(impl, input, minsup, ratio, jar)
    output = tempname() * ".txt"
    command = build_command(impl, input, minsup, ratio, output, jar)
    seconds, peak_mb, exceeded, ok = run_monitored(command)
    if exceeded
        rm(output; force = true)
        @warn "Memory limit exceeded; run discarded" impl input minsup limit_mb = MAX_MEMORY_MB
        return NaN, seconds, -1
    end
    if !ok || !isfile(output)
        error("Run failed for $impl on $input (minsup=$minsup)\ncommand: $command")
    end
    itemsets = count_itemsets(output)
    rm(output; force = true)
    return peak_mb, seconds, itemsets
end

# --------------------------------------------------------------------------
# Benchmark
# --------------------------------------------------------------------------

"Peak memory of each implementation on a tiny dataset (fixed start-up cost)."
function measure_baselines(impls, jar)
    toy = dataset_path("contextPasquier99")
    toy === nothing && error("Baseline dataset contextPasquier99.txt not found in data/toy/")
    ratio = 0.4
    minsup = max(1, ceil(Int, length(load_transactions(toy)) * ratio))
    baselines = Dict{String,Float64}()
    for impl in impls
        peaks = [measure(impl, toy, minsup, ratio, jar)[1] for _ in 1:RUNS]
        baselines[impl] = median(peaks)
        @info "Baseline" impl peak_mb = round(baselines[impl]; digits = 1)
    end
    return baselines
end

function main()
    jar = check_environment()
    impls = IMPLEMENTATIONS

    paths = [(name, dataset_path(name)) for name in DATASET_NAMES]
    missing_sets = [name for (name, path) in paths if path === nothing]
    isempty(missing_sets) || error("Missing dataset(s): $(join(missing_sets, ", "))")

    results_path = get(ENV, "MEMORY_RESULTS", joinpath(@__DIR__, "metrics/memory_result.csv"))
    summary_path = get(ENV, "MEMORY_SUMMARY", joinpath(@__DIR__, "metrics/memory_summary.csv"))
    mkpath(dirname(abspath(results_path)))

    baselines = measure_baselines(impls, jar)

    # (dataset, impl) => (peaks, nets, seconds, itemsets)
    summary = Dict{Tuple{String,String},NamedTuple}()
    order = Tuple{String,String}[]

    open(results_path, "w") do io
        println(io, "dataset,dataset_type,minsup_ratio,minsup_count,implementation,run,peak_mb,baseline_mb,net_mb,seconds,itemsets")
        for (name, path) in paths
            ratio = MEMORY_RATIOS[name]
            n_transactions = length(load_transactions(path))
            minsup = max(1, ceil(Int, n_transactions * ratio))
            @info "Dataset" name transactions = n_transactions minsup_ratio = ratio minsup

            for impl in impls
                peaks = Float64[]; seconds_list = Float64[]; itemsets = -1
                for run_id in 1:RUNS
                    peak, seconds, count = measure(impl, path, minsup, ratio, jar)
                    isnan(peak) && continue
                    net = max(0.0, peak - baselines[impl])
                    push!(peaks, peak); push!(seconds_list, seconds); itemsets = count
                    println(io, join([
                        csv_field(name), DATASET_TYPES[name], @sprintf("%.4f", ratio), minsup,
                        impl, run_id, @sprintf("%.2f", peak), @sprintf("%.2f", baselines[impl]),
                        @sprintf("%.2f", net), @sprintf("%.6f", seconds), count,
                    ], ","))
                    flush(io)
                end
                isempty(peaks) && continue
                key = (name, impl)
                push!(order, key)
                summary[key] = (
                    ratio = ratio, minsup = minsup,
                    peak = median(peaks), net = max(0.0, median(peaks) - baselines[impl]),
                    seconds = median(seconds_list), itemsets = itemsets,
                )
                @info "Measured" name impl peak_mb = round(summary[key].peak; digits = 1) net_mb = round(summary[key].net; digits = 1)
            end
        end
    end

    write_summary(summary_path, summary, order, impls)
    @info "Memory results written" results_path summary_path
end

function write_summary(path, summary, order, impls)
    println()
    @printf("%-12s %-10s %12s %12s %10s %10s\n", "dataset", "impl", "peak (MB)", "net (MB)", "time (s)", "itemsets")
    open(path, "w") do io
        println(io, "dataset,minsup_ratio,minsup_count,implementation,median_peak_mb,median_net_mb,median_seconds,itemsets,net_reduction_vs_basic_pct")
        for (name, impl) in order
            row = summary[(name, impl)]
            reduction = ""
            if impl != "basic" && haskey(summary, (name, "basic")) && summary[(name, "basic")].net > 0
                reduction = @sprintf("%.2f", 100 * (1 - row.net / summary[(name, "basic")].net))
            end
            @printf("%-12s %-10s %12.1f %12.1f %10.2f %10d\n", name, impl, row.peak, row.net, row.seconds, row.itemsets)
            println(io, join([
                csv_field(name), @sprintf("%.4f", row.ratio), row.minsup, impl,
                @sprintf("%.2f", row.peak), @sprintf("%.2f", row.net),
                @sprintf("%.6f", row.seconds), row.itemsets, reduction,
            ], ","))
        end
    end
    println()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
