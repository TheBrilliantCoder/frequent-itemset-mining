module Engine

using ..Models
using ..Ordering
using ..Properties
using ..Repository

export charm, charm_extend, run_charm

"""
    _frequent_pairs(nodes, minsup)

Compute all frequent 2-itemsets (F₂) from singleton nodes to calculate CHARM's
ordering weights.
"""
function _frequent_pairs(nodes::Vector{ITPair}, minsup::Int)::Vector{ITPair}
    pairs = ITPair[]
    for i in 1:length(nodes)-1
        for j in i+1:length(nodes)
            tids = intersect(nodes[i].tids, nodes[j].tids)
            length(tids) >= minsup || continue
            push!(pairs, ITPair(union(nodes[i].items, nodes[j].items), tids))
        end
    end
    return pairs
end

"""
    charm_extend(nodes, repo, minsup; frequent_pairs=[])

Recursively explore an equivalence class in depth-first order, applying CHARM
Properties 1–4 to merge closures, prune branches, and store closed itemsets.
"""
function charm_extend(
    nodes::Vector{ITPair},
    repo::ClosedItemsetRepository,
    minsup::Int;
    frequent_pairs = ITPair[],
)::Nothing
    n = length(nodes)
    removed = falses(n)

    for i in 1:n
        removed[i] && continue
        x = nodes[i]
        child_nodes = ITPair[]

        for j in i+1:n
            removed[j] && continue
            y = nodes[j]
            decision = charm_property(x, y, minsup)
            decision.frequent || continue
            candidate = decision.candidate::ITPair

            if decision.relation == EQUAL
                # Property 1: Merge Y into X and existing children, then prune Y.
                x = ITPair(union(x.items, y.items), x.tids)
                removed[j] = true
                for k in eachindex(child_nodes)
                    child = child_nodes[k]
                    child_nodes[k] = ITPair(union(child.items, y.items), child.tids)
                end
            elseif decision.relation == LEFT_SUBSET
                # Property 2: Merge Y into X and existing children, but keep Y.
                x = ITPair(union(x.items, y.items), x.tids)
                for k in eachindex(child_nodes)
                    child = child_nodes[k]
                    child_nodes[k] = ITPair(union(child.items, y.items), child.tids)
                end
            elseif decision.relation == RIGHT_SUBSET
                # Property 3: Prune Y from current level and queue candidate.
                removed[j] = true
                push!(child_nodes, candidate)
            else
                # Property 4: Keep both nodes and queue candidate for recursion.
                push!(child_nodes, candidate)
            end
        end

        if !isempty(child_nodes)
            ordered_children = order_itemsets_charm(child_nodes, frequent_pairs)
            charm_extend(
                ordered_children,
                repo,
                minsup;
                frequent_pairs = frequent_pairs,
            )
        end

        # Insert X into repository if it is not subsumed.
        consider!(repo, x)
    end
    return nothing
end

"""
    charm(db, minsup)

Main driver: filter frequent singletons, precompute F₂ item weights, sort the
root equivalence class, and run `charm_extend` to return all closed itemsets.
"""
function charm(db::VerticalDB, minsup::Int)::Vector{ClosedItemset}
    minsup >= 1 || throw(ArgumentError("minsup must be at least 1"))
    isempty(db) && return ClosedItemset[]

    nodes = ITPair[]
    for (item, tids) in db
        length(tids) >= minsup || continue
        push!(nodes, ITPair(Itemset([item]), copy(tids)))
    end
    isempty(nodes) && return ClosedItemset[]

    frequent_pairs = _frequent_pairs(nodes, minsup)
    weight_map = Ordering.build_weight_map(frequent_pairs)
    nodes = order_itemsets_charm(nodes, weight_map)

    repo = ClosedItemsetRepository()
    charm_extend(nodes, repo, minsup; frequent_pairs = weight_map)
    return results(repo)
end

"""
    run_charm(db, minsup)

Alias for `charm(db, minsup)`.
"""
run_charm(db::VerticalDB, minsup::Int)::Vector{ClosedItemset} = charm(db, minsup)

end # module Engine
