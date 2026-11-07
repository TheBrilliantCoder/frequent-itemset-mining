module Engine

using ..Models
using ..Ordering
using ..Properties
using ..Repository

export charm, charm_extend, run_charm

"""Build the frequent 2-itemset collection used by CHARM's ordering heuristic."""
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

Recursive CHARM-Extend over one prefix equivalence class.  `nodes` is kept as
an ordinary vector; removals required by Properties 1 and 3 are represented by
the local `removed` mask, avoiding mutation of the caller's vector.
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
                # Property 1: merge Y into X, remove Y, and propagate the
                # closure extension to candidates already created for X.
                x = ITPair(union(x.items, y.items), copy(x.tids))
                removed[j] = true
                for k in eachindex(child_nodes)
                    child = child_nodes[k]
                    child_nodes[k] = ITPair(
                        union(child.items, y.items), copy(child.tids)
                    )
                end
            elseif decision.relation == LEFT_SUBSET
                # Property 2: merge Y into X but retain Y for its own branch.
                x = ITPair(union(x.items, y.items), copy(x.tids))
                for k in eachindex(child_nodes)
                    child = child_nodes[k]
                    child_nodes[k] = ITPair(
                        union(child.items, y.items), copy(child.tids)
                    )
                end
            elseif decision.relation == RIGHT_SUBSET
                # Property 3: Y is redundant at this level; explore X ∪ Y
                # in the child class.
                removed[j] = true
                push!(child_nodes, candidate)
            else
                # Property 4: retain both siblings and explore the union.
                push!(child_nodes, candidate)
            end
        end

        if !isempty(child_nodes)
            ordered_children = isempty(frequent_pairs) ?
                order_itemsets(child_nodes) :
                order_itemsets_charm(child_nodes, frequent_pairs)
            charm_extend(
                ordered_children,
                repo,
                minsup;
                frequent_pairs = frequent_pairs,
            )
        end

        # X contains any closure extensions accumulated by Properties 1/2.
        consider!(repo, x)
    end
    return nothing
end

"""
    charm(db, minsup)

Mine frequent closed itemsets from a vertical database using CHARM's
tidset-based search.  `minsup` is an absolute transaction count.
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
    nodes = isempty(frequent_pairs) ?
        order_itemsets(nodes) :
        order_itemsets_charm(nodes, frequent_pairs)

    repo = ClosedItemsetRepository()
    charm_extend(nodes, repo, minsup; frequent_pairs = frequent_pairs)
    return results(repo)
end

"""Contract-compatible alias for [`charm`](@ref)."""
run_charm(db::VerticalDB, minsup::Int)::Vector{ClosedItemset} = charm(db, minsup)

end # module Engine
