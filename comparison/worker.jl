"""
    worker.jl

Child process used by the benchmarks to run one Julia implementation.

    julia --project=. comparison/worker.jl IMPL INPUT MINSUP OUTPUT

`IMPL` is `basic` (`mine_file`) or `optimized` (`mine_file_bit`).  `MINSUP` is
an absolute transaction count.  The closed itemsets are written to `OUTPUT` in
SPMF format.  Not meant to be run by hand.
"""

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))

include(joinpath(REPOSITORY_ROOT, "src", "CharmMining.jl"))
using .CharmMining

function main()
    length(ARGS) == 4 || error("Usage: worker.jl IMPL INPUT MINSUP OUTPUT")
    impl, input, minsup_text, output = ARGS
    minsup = parse(Int, minsup_text)
    if impl == "basic"
        mine_file(input; minsup = minsup, output_path = output)
    elseif impl == "optimized"
        mine_file_bit(input; minsup = minsup, output_path = output)
    else
        error("Unknown implementation: $impl (expected basic or optimized)")
    end
    return nothing
end

main()
