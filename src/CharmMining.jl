module CharmMining

include("models.jl")
include("ordering.jl")
include("properties.jl")
include("repository.jl")
include("data.jl")
include("engine.jl")
include("pipeline.jl")

using .Models
using .Data
using .Ordering
using .Properties
using .Repository
using .Engine
using .Pipeline

export Item, Tid, Itemset, Tidset, VerticalDB, ITPair, ClosedItemset, support
export load_transactions, to_vertical, frequent_singletons, export_result
export charm_weight, charm_ordering_key, order_itemsets_charm
export CharmRelation, EQUAL, LEFT_SUBSET, RIGHT_SUBSET, INCOMPARABLE,
       classify_relation, combine_nodes, charm_property
export ClosedItemsetRepository, consider!, results
export charm, charm_extend, run_charm, mine_file

end # module CharmMining
