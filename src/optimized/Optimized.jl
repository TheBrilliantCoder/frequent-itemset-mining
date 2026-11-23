module Optimized

using ..Models: Item, ClosedItemset
using ..Properties: CharmRelation, EQUAL, LEFT_SUBSET, RIGHT_SUBSET, INCOMPARABLE
using ..Data: load_transactions, export_result

include("models.jl")
include("ordering.jl")
include("properties.jl")
include("repository.jl")
include("engine.jl")

export FastBitTidset, FastITNode, BitVerticalDB, to_vertical_bit,
       sorted_union, sorted_issubset, fast_support,
       compute_f2_weights, node_charm_weight, order_nodes_charm!,
       FastPropertyResult, charm_property_bit,
       FastRepository, consider_bit!, results_bit,
       charm_extend_bit, charm_bit, run_charm_bit, mine_file_bit

end # module Optimized