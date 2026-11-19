"""
    compare_memory.jl

Peak-memory evaluation (Task 4) for CHARM:

  * basic     : Julia implementation without the optimization
  * optimized : Julia implementation with the optimization
                (needs `CharmMining.mine_file_optimized`; skipped until it exists)
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
    MEMORY_RESULTS    detailed CSV path             (default comparison/memory_result.csv)
    MEMORY_SUMMARY    summary CSV path              (default comparison/memory_summary.csv)
"""

using Printf
using Statistics

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))

const DATASET_NAMES = ["chess", "mushrooms", "retail", "T10I4D100K", "accidents"]

# One "median" support ratio per dataset: the middle of the range used in
# compare_time.jl for the dataset's density class.
const MEMORY_RATIOS = Dict(
    "chess"      => 0.65,
    "mushrooms"  => 0.35,
    "accidents"  => 0.65,
    "retail"     => 0.04,
    "T10I4D100K" => 0.04,
)
const DATASET_TYPES = Dict(
    "chess" => "very dense", "mushrooms" => "dense", "accidents" => "very dense",
    "retail" => "sparse", "T10I4D100K" => "sparse",
)

const IMPLEMENTATIONS = ["basic", "optimized", "spmf"]
const SPMF_ALGORITHM = "Charm_bitset"
const RUNS = parse(Int, get(ENV, "MEMORY_RUNS", "3"))
const MAX_MEMORY_MB = parse(Float64, get(ENV, "MEMORY_LIMIT_MB", "6000"))

include(joinpath(REPOSITORY_ROOT, "src", "CharmMining.jl"))
using .CharmMining

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

function dataset_path(name::AbstractString)
    for path in (
        joinpath(REPOSITORY_ROOT, "data", "toy", name * ".txt"),
        joinpath(REPOSITORY_ROOT, "data", name * ".txt"),
        joinpath(REPOSITORY_ROOT, "data", "benchmark", name * ".txt"),
    )
        isfile(path) && return path
    end
    return nothing
end

spmf_path() = begin
    configured = get(ENV, "SPMF_JAR", "")
    isempty(configured) ? joinpath(REPOSITORY_ROOT, "tools", "spmf.jar") : abspath(configured)
end

optimized_available() = isdefined(CharmMining, :mine_file_optimized)

count_itemsets(path) = count(line -> occursin("#SUP:", line), eachline(path))

csv_field(value) = begin
    text = string(value)
    occursin(r"[,\"\n]", text) ? '"' * replace(text, '"' => "\"\"") * '"' : text
end

"Peak RSS (MB) of a running process: VmHWM, falling back to VmRSS."
function process_peak_mb(pid)
    status_path = "/proc/$pid/status"
    isfile(status_path) || return 0.0
    hwm = 0.0
    rss = 0.0
    try
        for line in eachline(status_path)
            if startswith(line, "VmHWM:")
                hwm = parse(Float64, split(line)[2]) / 1024.0
            elseif startswith(line, "VmRSS:")
                rss = parse(Float64, split(line)[2]) / 1024.0
            end
        end
    catch
        # process vanished while reading
    end
    return max(hwm, rss)
end

"Run `command` and return (seconds, peak_mb, exceeded, ok)."
function run_monitored(command::Cmd)
    pid_file = tempname()
    wrapped_command = Cmd(vcat(
        ["/bin/sh", "-c", "echo \$\$ > \"$pid_file\"; exec \"\$@\"", "monitored"],
        command.exec,
    ))
    started_ns = time_ns()
    process = run(wrapped_command; wait = false)
    pid = nothing
    while pid === nothing && process_running(process)
        if isfile(pid_file)
            pid = tryparse(Int, strip(read(pid_file, String)))
        end
        pid === nothing && sleep(0.001)
    end
    peak_mb = 0.0
    exceeded = false
    if pid !== nothing
        while process_running(process)
            current = process_peak_mb(pid)
            peak_mb = max(peak_mb, current)
            if current > MAX_MEMORY_MB
                exceeded = true
                kill(process, Base.SIGKILL)
                break
            end
            sleep(0.005)
        end
    end
    try
        wait(process)
    catch err
        err isa ProcessFailedException || rethrow()
    end
    seconds = (time_ns() - started_ns) / 1.0e9
    rm(pid_file; force = true)
    ok = !exceeded && process.exitcode == 0
    return seconds, peak_mb, exceeded, ok
end

function build_command(impl, input, minsup, ratio, output, jar)
    if impl == "spmf"
        java_opts = split(get(ENV, "SPMF_JAVA_OPTS", ""))
        percent = string(round(ratio * 100; digits = 6)) * "%"
        return `java $java_opts -jar $jar run $SPMF_ALGORITHM $input $output $percent`
    end
    return `$(Base.julia_cmd()) --project=$REPOSITORY_ROOT $(@__FILE__) --worker $impl $input $minsup $output`
end

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
# Worker (child process for the Julia implementations)
# --------------------------------------------------------------------------

function worker()
    length(ARGS) == 5 || error("Worker usage: --worker IMPL INPUT MINSUP OUTPUT")
    impl, input, minsup_text, output = ARGS[2:5]
    minsup = parse(Int, minsup_text)
    if impl == "basic"
        mine_file(input; minsup = minsup, output_path = output)
    elseif impl == "optimized"
        optimized_available() || error("CharmMining.mine_file_optimized is not defined")
        CharmMining.mine_file_optimized(input; minsup = minsup, output_path = output)
    else
        error("Unknown implementation: $impl")
    end
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
    jar = spmf_path()
    isfile(jar) || error("SPMF jar not found at $jar. Set SPMF_JAR.")
    Sys.which("java") === nothing && error("Java was not found on PATH.")
    Sys.islinux() || error("This script reads /proc and only works on Linux.")

    impls = filter(IMPLEMENTATIONS) do impl
        if impl == "optimized" && !optimized_available()
            @warn "CharmMining.mine_file_optimized not defined; skipping the optimized implementation"
            return false
        end
        return true
    end

    paths = [(name, dataset_path(name)) for name in DATASET_NAMES]
    missing_sets = [name for (name, path) in paths if path === nothing]
    isempty(missing_sets) || error("Missing dataset(s): $(join(missing_sets, ", "))")

    results_path = get(ENV, "MEMORY_RESULTS", joinpath(@__DIR__, "memory_result.csv"))
    summary_path = get(ENV, "MEMORY_SUMMARY", joinpath(@__DIR__, "memory_summary.csv"))
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
    isempty(ARGS) || first(ARGS) != "--worker" ? main() : worker()
end
