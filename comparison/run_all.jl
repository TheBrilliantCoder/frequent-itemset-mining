"""
    run_all.jl

Run the whole benchmark: the three comparisons (basic vs optimized vs SPMF),
then the plots.  From the repository root:

    julia --project=. comparison/run_all.jl

CSV files go to comparison/metrics/, SVG plots to comparison/plots/.  Any
environment variable accepted by the individual scripts (SPMF_JAR, TIME_RUNS,
TIME_DATASETS, MEMORY_RUNS, SCALABILITY_DATASET, ...) is passed through.

Pass `time`, `memory` and/or `scalability` to run only those parts:

    julia --project=. comparison/run_all.jl time memory
"""

const STEPS = [
    "time" => ["compare_time.jl", "plot_time.jl"],
    "memory" => ["compare_memory.jl", "plot_memory.jl"],
    "scalability" => ["compare_scalability.jl", "plot_scalability.jl"],
]

function main()
    chosen = isempty(ARGS) ? first.(STEPS) : ARGS
    unknown = setdiff(chosen, first.(STEPS))
    isempty(unknown) || error("Unknown part(s): $(join(unknown, ", ")). Use: $(join(first.(STEPS), ", "))")

    root = normpath(joinpath(@__DIR__, ".."))
    for (name, scripts) in STEPS
        name in chosen || continue
        for script in scripts
            @info "Running $script"
            run(`$(Base.julia_cmd()) --project=$root $(joinpath(@__DIR__, script))`)
        end
    end
    @info "Done" metrics = joinpath(@__DIR__, "metrics") plots = joinpath(@__DIR__, "plots")
end

main()
