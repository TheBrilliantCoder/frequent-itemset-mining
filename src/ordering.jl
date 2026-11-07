module Ordering

using ..Models

export ordering_key, order_itemsets,
       charm_weight, charm_ordering_key, order_itemsets_charm

"""
Khóa sắp xếp: support tăng dần; nếu hòa thì so sánh vector item đã sort theo từ điển.
"""
function ordering_key(node::ITPair)::Tuple{Int, Vector{Item}}
    return (support(node), sort!(collect(node.items)))
end

"""
Sắp xếp mảng ITPair theo quy tắc tất định, không làm biến đổi mảng đầu vào.
"""
function order_itemsets(nodes::Vector{ITPair})::Vector{ITPair}
    return sort(nodes, by = ordering_key)
end

"""
    charm_weight(item, frequent_pairs)

Return the CHARM ordering weight of `item`.

`frequent_pairs` is a collection of `ITPair`s representing frequent
2-itemsets (`F₂`).  The weight is the sum of the supports of the pairs that
contain `item`, as described in `docs/charm.md`:

    w(x) = Σ support(xy), for xy ∈ F₂

Pairs with an itemset size other than two are ignored.  This makes the
function safe to use with a mixed collection of candidate nodes.
"""
function charm_weight(item::Item, frequent_pairs)::Int
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

Build the CHARM ordering key for an IT-pair.  Lower total weight is visited
first.  Support and lexicographically sorted items are deterministic
tie-breakers, so the result does not depend on `Dict`/`Set` iteration order.
"""
function charm_ordering_key(
    node::ITPair,
    frequent_pairs,
)::Tuple{Int, Int, Vector{Item}}
    weight = sum(charm_weight(item, frequent_pairs) for item in node.items)
    return (weight, support(node), sort!(collect(node.items)))
end

"""
    order_itemsets_charm(nodes, frequent_pairs)

Return a new vector ordered by the CHARM weight heuristic.  The input vector
is not modified.
"""
function order_itemsets_charm(
    nodes::Vector{ITPair},
    frequent_pairs,
)::Vector{ITPair}
    return sort(nodes, by = node -> charm_ordering_key(node, frequent_pairs))
end

end # module Ordering
