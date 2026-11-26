"""
    compare_time.jl

Benchmark both Julia CHARM implementations (baseline `mine_file` and optimized
`mine_file_bit`) against SPMF's Charm_bitset.

The benchmark uses the same percentage support thresholds for both programs.
SPMF accepts percentages, while the Julia implementation accepts an absolute
transaction count, so the latter is calculated with `ceil` for every dataset.

Run from the repository root with:

    julia --project=. comparison/compare_time.jl

Set `SPMF_JAR` when the jar is not at `tools/spmf.jar`.  Results are written to
`comparison/time_result.csv` (or to the path in `TIME_RESULTS`).
"""

using Printf

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const DATASET_NAMES = [
    # "contextPasquier99",
    "chess",
    "mushrooms",
    "retail",
    "T10I4D100K",
    "accidents",
]

# Dense datasets need higher supports to keep the generated closed-itemset
# space manageable.  Sparse datasets use lower supports so that meaningful
# patterns are still found.  Every dataset is tested at seven high-to-low
# points within its class range.
const DATASET_TYPES = Dict(
    "chess" => "very dense",
    "mushrooms" => "dense",
    "accidents" => "very dense",
    "retail" => "sparse",
    "T10I4D100K" => "sparse",
)
const MIN_SUPPORT_RATIOS = Dict(
    "very dense" => [0.9, 0.80, 0.70, 0.60, 0.5, 0.4],
    "dense" => [0.80, 0.60, 0.50, 0.2, 0.10, 0.05],
    "sparse" => [0.10, 0.08, 0.06, 0.04, 0.02, 0.01, 0.005],
)
const SPMF_ALGORITHM = "Charm_bitset"
const MAX_MEMORY_MB = 2000.0

include(joinpath(REPOSITORY_ROOT, "src", "CharmMining.jl"))
using .CharmMining

function dataset_path(name::AbstractString)
    candidates = (
        joinpath(REPOSITORY_ROOT, "data", "toy", name * ".txt"),
        joinpath(REPOSITORY_ROOT, "data", name * ".txt"),
        joinpath(REPOSITORY_ROOT, "data", "benchmark", name * ".txt"),
    )
    for path in candidates
        isfile(path) && return path
    end
    return nothing
end

function spmf_path()
    configured = get(ENV, "SPMF_JAR", "")
    if !isempty(configured)
        return abspath(configured)
    end
    return joinpath(REPOSITORY_ROOT, "tools", "spmf.jar")
end

function csv_field(value)
    text = string(value)
    return occursin(r"[,\"\n]", text) ? '"' * replace(text, '"' => "\"\"") * '"' : text
end

function write_header(io)
    println(io, "dataset,dataset_type,minsup_ratio,minsup_count,julia_itemsets,optimized_itemsets,spmf_itemsets,julia_seconds,optimized_seconds,spmf_seconds")
end

function process_memory_mb(pid)
    # Linux reports the current resident set in /proc while the process runs.
    status_path = "/proc/$pid/status"
    isfile(status_path) || return 0.0
    for line in eachline(status_path)
        startswith(line, "VmRSS:") || continue
        return parse(Float64, split(line)[2]) / 1024.0 # kB -> MB
    end
    return 0.0
end

function run_monitored(command::Cmd)
    pid_file = tempname()
    # Base.Process does not expose the OS pid on all supported Julia versions.
    # The wrapper records it before replacing itself with the target process.
    wrapped_command = Cmd(vcat(
        ["/bin/sh", "-c", "echo \$\$ > \"$pid_file\"; exec \"\$@\"", "monitored"],
        command.exec,
    ))
    process = run(wrapped_command; wait = false)
    pid = nothing
    while pid === nothing && process_running(process)
        if isfile(pid_file)
            pid = parse(Int, strip(read(pid_file, String)))
        else
            sleep(0.001)
        end
    end
    if pid === nothing
        wait(process)
        rm(pid_file; force = true)
        return 0.0, 0.0, false
    end
    peak_memory_mb = 0.0
    exceeded = false
    started_ns = time_ns()
    try
        while process_running(process)
            current_memory_mb = process_memory_mb(pid)
            peak_memory_mb = max(peak_memory_mb, current_memory_mb)
            if current_memory_mb > MAX_MEMORY_MB
                exceeded = true
                kill(process, Base.SIGKILL)
                break
            end
            sleep(0.01)
        end
    finally
        # Reap the child even when it was killed by the memory guard.
        try
            wait(process)
        catch err
            err isa ProcessFailedException || rethrow()
        end
    end
    rm(pid_file; force = true)
    return (time_ns() - started_ns) / 1.0e9, peak_memory_mb, exceeded
end

function memory_allowed(dataset, implementation, exceeded, memory_mb)
    if exceeded
        @warn "Killed and skipped minsup because memory limit was exceeded" dataset implementation memory_mb=round(memory_mb; digits = 2) limit_mb=MAX_MEMORY_MB
        return false
    end
    return true
end

function count_itemsets(path::AbstractString)
    count(line -> occursin("#SUP:", line), eachline(path))
end

function run_benchmark(dataset::AbstractString, input_path::AbstractString, 
                       jar::AbstractString, io)
    transactions = load_transactions(input_path)
    transaction_count = length(transactions)
    transaction_count > 0 || error("Dataset is empty: $input_path")
    dataset_type = DATASET_TYPES[dataset]
    support_ratios = MIN_SUPPORT_RATIOS[dataset_type]

    for ratio in support_ratios
        minsup = max(1, ceil(Int, transaction_count * ratio))
        julia_output = tempname() * ".txt"
        command = `$(Base.julia_cmd()) --project=$REPOSITORY_ROOT $(@__FILE__) --worker basic $input_path $minsup $julia_output`
        julia_seconds, julia_memory_mb, julia_exceeded = run_monitored(command)
        if !memory_allowed(dataset, "Julia", julia_exceeded, julia_memory_mb)
            rm(julia_output; force = true)
            continue
        end
        julia_itemsets = count_itemsets(julia_output)
        rm(julia_output; force = true)

        optimized_output = tempname() * ".txt"
        command = `$(Base.julia_cmd()) --project=$REPOSITORY_ROOT $(@__FILE__) --worker optimized $input_path $minsup $optimized_output`
        optimized_seconds, optimized_memory_mb, optimized_exceeded = run_monitored(command)
        if !memory_allowed(dataset, "Julia optimized", optimized_exceeded, optimized_memory_mb)
            rm(optimized_output; force = true)
            continue
        end
        optimized_itemsets = count_itemsets(optimized_output)
        rm(optimized_output; force = true)

        spmf_output = tempname() * ".txt"
        command = `java -jar $jar run $SPMF_ALGORITHM $input_path $spmf_output $(string(round(ratio * 100; digits = 6))*"%")`
        spmf_seconds, spmf_memory_mb, spmf_exceeded = run_monitored(command)
        if !memory_allowed(dataset, "SPMF", spmf_exceeded, spmf_memory_mb)
            rm(spmf_output; force = true)
            continue
        end
        spmf_itemsets = count_itemsets(spmf_output)
        rm(spmf_output; force = true)

        println(io, join([
            csv_field(dataset),
            dataset_type,
            @sprintf("%.6f", ratio),
            string(minsup),
            string(julia_itemsets),
            string(optimized_itemsets),
            string(spmf_itemsets),
            @sprintf("%.9f", julia_seconds),
            @sprintf("%.9f", optimized_seconds),
            @sprintf("%.9f", spmf_seconds),
        ], ","))
        flush(io)
        @info "Completed benchmark point" dataset minsup_ratio=ratio minsup julia_seconds optimized_seconds spmf_seconds
    end
end

function worker()
    length(ARGS) == 5 || error("Worker usage: --worker basic|optimized INPUT MINSUP OUTPUT")
    implementation, input_path, minsup_text, output_path = ARGS[2:5]
    mine = implementation == "optimized" ? mine_file_bit :
           implementation == "basic" ? mine_file :
           error("Unknown implementation: $implementation")
    mine(input_path; minsup = parse(Int, minsup_text), output_path = output_path)
end

function main()
    jar = spmf_path()
    isfile(jar) || error("SPMF jar not found at $jar. Download it to tools/spmf.jar or set SPMF_JAR.")
    Sys.which("java") === nothing && error("Java was not found on PATH.")

    output_path = get(ENV, "TIME_RESULTS", joinpath(@__DIR__, "time_result.csv"))
    mkpath(dirname(abspath(output_path)))

    paths = [(name, dataset_path(name)) for name in DATASET_NAMES]
    missing = [name for (name, path) in paths if path === nothing]
    isempty(missing) || error("Missing dataset(s): $(join(missing, ", ")). Expected them in data/benchmark/.")

    open(output_path, "w") do io
        write_header(io)
        for (name, path) in paths
            @info "Benchmarking dataset" dataset=name path
            run_benchmark(name, path, jar, io)
        end
    end
    @info "Timing comparison written" output_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) || first(ARGS) != "--worker" ? main() : worker()
end
