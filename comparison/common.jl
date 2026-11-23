"""
    common.jl

Code shared by the three benchmark scripts in this folder
(`compare_time.jl`, `compare_memory.jl`, `compare_scalability.jl`).

The three implementations that are compared everywhere:

  * basic     : `CharmMining.mine_file`      (BitSet tidsets)
  * optimized : `CharmMining.mine_file_bit`  (BitVector + SIMD)
  * spmf      : SPMF `Charm_bitset` (Java reference)

Every implementation always runs in its own OS process (Julia ones through
`comparison/worker.jl`, SPMF through `java -jar`), so wall time and peak
memory are measured the same way for all of them.

This file is meant to be `include`d, not run.
"""

using Printf
using Statistics

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const WORKER_SCRIPT = joinpath(@__DIR__, "worker.jl")

const IMPLEMENTATIONS = ["basic", "optimized", "spmf"]
const SPMF_ALGORITHM = "Charm_bitset"
const MAX_MEMORY_MB = parse(Float64, get(ENV, "MEMORY_LIMIT_MB", "6000"))

# Tiny dataset used to measure the fixed start-up cost of Julia / the JVM.
const BASELINE_DATASET = "contextPasquier99"
const BASELINE_RATIO = 0.4

const DATASET_NAMES = ["chess", "mushrooms", "retail", "T10I4D100K", "accidents"]
const DATASET_TYPES = Dict(
    "chess" => "very dense",
    "mushrooms" => "dense",
    "accidents" => "very dense",
    "retail" => "sparse",
    "T10I4D100K" => "sparse",
)

include(joinpath(REPOSITORY_ROOT, "src", "CharmMining.jl"))
using .CharmMining

# --------------------------------------------------------------------------
# Files and small helpers
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

function spmf_path()
    configured = get(ENV, "SPMF_JAR", "")
    return isempty(configured) ? joinpath(REPOSITORY_ROOT, "tools", "spmf.jar") : abspath(configured)
end

count_itemsets(path) = count(line -> occursin("#SUP:", line), eachline(path))

function csv_field(value)
    text = string(value)
    return occursin(r"[,\"\n]", text) ? '"' * replace(text, '"' => "\"\"") * '"' : text
end

"Check that java, the SPMF jar and /proc are available. Returns the jar path."
function check_environment()
    jar = spmf_path()
    isfile(jar) || error("SPMF jar not found at $jar. Set SPMF_JAR.")
    Sys.which("java") === nothing && error("Java was not found on PATH.")
    Sys.islinux() || error("The benchmark reads /proc and only works on Linux.")
    return jar
end

"Path of the tiny baseline dataset and the absolute minsup used on it."
function baseline_minsup()
    toy = dataset_path(BASELINE_DATASET)
    toy === nothing && error("Baseline dataset $BASELINE_DATASET.txt not found in data/toy/")
    return toy, max(1, ceil(Int, length(load_transactions(toy)) * BASELINE_RATIO))
end

# --------------------------------------------------------------------------
# Running one implementation in a monitored child process
# --------------------------------------------------------------------------

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
    # The wrapper records the pid, then replaces itself with the target process.
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

"Command line that runs implementation `impl` (basic / optimized / spmf)."
function build_command(impl, input, minsup, ratio, output, jar)
    impl in IMPLEMENTATIONS || error("Unknown implementation: $impl")
    if impl == "spmf"
        java_opts = split(get(ENV, "SPMF_JAVA_OPTS", ""))
        percent = string(round(ratio * 100; digits = 6)) * "%"
        return `java $java_opts -jar $jar run $SPMF_ALGORITHM $input $output $percent`
    end
    return `$(Base.julia_cmd()) --project=$REPOSITORY_ROOT $WORKER_SCRIPT $impl $input $minsup $output`
end

"""
One monitored run of `impl`.  Returns
`(seconds, peak_mb, itemsets, status)` with status `"ok"`, `"mem_exceeded"`
or `"failed"`; `itemsets` is -1 unless the status is `"ok"`.
"""
function run_point(impl, input, minsup, ratio, jar)
    output = tempname() * ".txt"
    command = build_command(impl, input, minsup, ratio, output, jar)
    seconds, peak_mb, exceeded, ok = run_monitored(command)
    status = exceeded ? "mem_exceeded" : (ok && isfile(output) ? "ok" : "failed")
    itemsets = status == "ok" ? count_itemsets(output) : -1
    rm(output; force = true)
    if status == "mem_exceeded"
        @warn "Memory limit exceeded; run discarded" impl input minsup limit_mb = MAX_MEMORY_MB
    elseif status == "failed"
        @warn "Run failed" impl input minsup command
    end
    return (seconds = seconds, peak_mb = peak_mb, itemsets = itemsets, status = status)
end
