"""
    compare_time.jl

Runtime benchmark of the three CHARM implementations:

  * basic     : Julia implementation without the optimization
  * optimized : Julia implementation with BitVector/SIMD (`mine_file_bit`)
  * spmf      : SPMF `Charm_bitset` reference

All three use the same percentage support thresholds.  SPMF accepts
percentages, while the Julia implementations accept an absolute transaction
count, which is calculated with `ceil` for every dataset.

Every run is a separate OS process.  Wall time includes the fixed start-up cost
of Julia or the JVM, so the script measures that cost once per implementation
on a tiny dataset and also reports `net_seconds = seconds - baseline`.

Run from the repository root:

    julia --project=. comparison/compare_time.jl

Environment variables (all optional):

    SPMF_JAR          path to spmf.jar              (default tools/spmf.jar)
    SPMF_JAVA_OPTS    extra JVM flags, e.g. "-Xmx2g"
    TIME_RUNS         repetitions per point, median is kept (default 1)
    TIME_DATASETS     comma separated subset, e.g. "chess,mushrooms"
    MEMORY_LIMIT_MB   kill a run above this RSS     (default 6000)
    TIME_RESULTS      output CSV (default comparison/metrics/time_result.csv)

Output: one row per (dataset, minsup, implementation).  `status` is `ok`,
`mem_exceeded` or `failed`; the numeric columns are empty unless it is `ok`.
"""

include(joinpath(@__DIR__, "common.jl"))

# Dense datasets need higher supports to keep the generated closed-itemset
# space manageable.  Sparse datasets use lower supports so that meaningful
# patterns are still found.
const MIN_SUPPORT_RATIOS = Dict(
    "very dense" => [0.9, 0.80, 0.70, 0.60, 0.5, 0.4],
    "dense" => [0.80, 0.60, 0.50, 0.2, 0.10, 0.05],
    "sparse" => [0.10, 0.08, 0.06, 0.04, 0.02, 0.01, 0.005],
)
const RUNS = parse(Int, get(ENV, "TIME_RUNS", "1"))

function write_header(io)
    println(io, "dataset,dataset_type,minsup_ratio,minsup_count,implementation,seconds,net_seconds,peak_mb,itemsets,status")
end

"Median of `RUNS` monitored runs. Returns a NamedTuple like `run_point`."
function measure(impl, input, minsup, ratio, jar)
    runs = [run_point(impl, input, minsup, ratio, jar) for _ in 1:RUNS]
    good = filter(r -> r.status == "ok", runs)
    isempty(good) && return last(runs)
    return (
        seconds = median([r.seconds for r in good]),
        peak_mb = median([r.peak_mb for r in good]),
        itemsets = last(good).itemsets,
        status = "ok",
    )
end

"Start-up cost (wall seconds) of each implementation on a tiny dataset."
function measure_baselines(jar)
    toy, minsup = baseline_minsup()
    baselines = Dict{String,Float64}()
    for impl in IMPLEMENTATIONS
        result = measure(impl, toy, minsup, BASELINE_RATIO, jar)
        baselines[impl] = result.status == "ok" ? result.seconds : 0.0
        @info "Baseline" impl seconds = round(baselines[impl]; digits = 3)
    end
    return baselines
end

function write_row(io, dataset, ratio, minsup, impl, result, baseline)
    ok = result.status == "ok"
    println(io, join([
        csv_field(dataset),
        DATASET_TYPES[dataset],
        @sprintf("%.6f", ratio),
        string(minsup),
        impl,
        ok ? @sprintf("%.6f", result.seconds) : "",
        ok ? @sprintf("%.6f", max(0.0, result.seconds - baseline)) : "",
        ok ? @sprintf("%.2f", result.peak_mb) : "",
        ok ? string(result.itemsets) : "",
        result.status,
    ], ","))
    flush(io)
end

function run_benchmark(dataset, input_path, jar, baselines, io)
    transaction_count = length(load_transactions(input_path))
    transaction_count > 0 || error("Dataset is empty: $input_path")

    for ratio in MIN_SUPPORT_RATIOS[DATASET_TYPES[dataset]]
        minsup = max(1, ceil(Int, transaction_count * ratio))
        counts = Dict{String,Int}()
        for impl in IMPLEMENTATIONS
            result = measure(impl, input_path, minsup, ratio, jar)
            write_row(io, dataset, ratio, minsup, impl, result, baselines[impl])
            result.status == "ok" && (counts[impl] = result.itemsets)
            @info "Benchmark point" dataset minsup_ratio = ratio minsup impl status = result.status seconds = round(result.seconds; digits = 3)
        end
        if length(unique(values(counts))) > 1
            @warn "Implementations disagree on the number of closed itemsets" dataset minsup counts
        end
    end
end

function main()
    jar = check_environment()

    wanted = get(ENV, "TIME_DATASETS", "")
    names = isempty(wanted) ? DATASET_NAMES : String.(split(wanted, ','))
    for name in names
        haskey(DATASET_TYPES, name) || error("Unknown dataset: $name (known: $(join(DATASET_NAMES, ", ")))")
    end
    paths = [(name, dataset_path(name)) for name in names]
    missing_sets = [name for (name, path) in paths if path === nothing]
    isempty(missing_sets) || error("Missing dataset(s): $(join(missing_sets, ", ")). Expected them in data/benchmark/ (see README).")

    output_path = get(ENV, "TIME_RESULTS", joinpath(@__DIR__, "metrics", "time_result.csv"))
    mkpath(dirname(abspath(output_path)))

    baselines = measure_baselines(jar)
    open(output_path, "w") do io
        write_header(io)
        for (name, path) in paths
            @info "Benchmarking dataset" dataset = name path
            run_benchmark(name, path, jar, baselines, io)
        end
    end
    @info "Timing comparison written" output_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
