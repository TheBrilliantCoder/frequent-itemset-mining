module Ordering

using ..Models

export charm_weight, charm_ordering_key, order_itemsets_charm, build_weight_map

"""
    build_weight_map(frequent_pairs)

Precompute a lookup dictionary mapping each item to the total support of all
frequent 2-itemsets containing it, enabling O(1) weight lookups during sorting.
"""
function build_weight_map(frequent_pairs)::Dict{Item, Int}
    weights = Dict{Item, Int}()
    for pair in frequent_pairs
        length(pair.items) == 2 || continue
        supp = support(pair)
        for item in pair.items
            weights[item] = get(weights, item, 0) + supp
        end
    end
    return weights
end

"""
    charm_weight(item, frequent_pairs)

Return the CHARM weight of `item` (sum of supports of frequent 2-itemsets
containing it). Uses O(1) lookup if passed a precomputed weight dictionary,
or falls back to scanning `frequent_pairs`[cite: 4].
"""
function charm_weight(item::Item, frequent_pairs)::Int
    frequent_pairs isa Dict{Item, Int} && return get(frequent_pairs, item, 0)
    weight = 0
    for pair in frequent_pairs
        length(pair.items) == 2 || continue
        item in pair.items || continue
        weight += support(pair)
    end
    return weight
end

"""
    charm_ordering_key(node, frequent_pairs)

Create a deterministic sort key `(total_weight, support, sorted_items)` for an
`ITPair` so lower weights are visited first, with support and lexicographical
order as tie-breakers[cite: 4].
"""
function charm_ordering_key(
    node::ITPair,
    frequent_pairs,
)::Tuple{Int, Int, Vector{Item}}
    weight = sum(charm_weight(item, frequent_pairs) for item in node.items; init = 0)
    return (weight, support(node), sort!(collect(node.items)))
end

"""
    order_itemsets_charm(nodes, frequent_pairs)

Return a new vector of `ITPair`s sorted in increasing order of CHARM weight
using a precomputed weight map[cite: 4].
"""
function order_itemsets_charm(
    nodes::Vector{ITPair},
    frequent_pairs,
)::Vector{ITPair}
    weights = frequent_pairs isa Dict{Item, Int} ? frequent_pairs : build_weight_map(frequent_pairs)
    return sort(nodes, by = node -> charm_ordering_key(node, weights))
end

end # module Ordering
