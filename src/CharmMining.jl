module CharmMining

include("models.jl")
include("ordering.jl")
include("properties.jl")
include("repository.jl")
include("data.jl")
include("engine.jl")
include("pipeline.jl")
include("rules.jl")
include("optimized/Optimized.jl")

using .Models
using .Data
using .Ordering
using .Properties
using .Repository
using .Engine
using .Pipeline
using .Rules
using .Optimized

export Item, Tid, Itemset, Tidset, VerticalDB, ITPair, ClosedItemset, support
export load_transactions, to_vertical, frequent_singletons, export_result
export charm_weight, charm_ordering_key, order_itemsets_charm
export CharmRelation, EQUAL, LEFT_SUBSET, RIGHT_SUBSET, INCOMPARABLE,
       classify_relation, combine_nodes, charm_property
export ClosedItemsetRepository, tid_checksum, consider!, results
export charm, charm_extend, run_charm, mine_file
export AssociationRule, ClosureSupportIndex, build_support_index, support_of,
       generate_rules, top_rules_by_lift

# Export toàn bộ API của bản Optimized ra Main
export FastBitTidset, FastITNode, BitVerticalDB, to_vertical_bit,
       sorted_union, sorted_issubset, fast_support,
       compute_f2_weights, node_charm_weight, order_nodes_charm!,
       FastPropertyResult, charm_property_bit,
       FastRepository, consider_bit!, results_bit,
       charm_extend_bit, charm_bit, run_charm_bit, mine_file_bit

end # module CharmMining