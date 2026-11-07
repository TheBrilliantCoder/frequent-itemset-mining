module Properties

using ..Models

export CharmRelation, EQUAL, LEFT_SUBSET, RIGHT_SUBSET, INCOMPARABLE,
       CharmPropertyResult, classify_relation, combine_nodes, charm_property

"""The four possible CHARM relations between two tidsets."""
@enum CharmRelation begin
    EQUAL          # t(X) == t(Y)
    LEFT_SUBSET    # t(X) ⊊ t(Y)
    RIGHT_SUBSET   # t(X) ⊋ t(Y)
    INCOMPARABLE   # neither tidset contains the other
end

"""
    classify_relation(tx, ty)

Classify the relation between `tx` and `ty`.  The equality check must happen
first because equality is also a subset relation.
"""
function classify_relation(tx::Tidset, ty::Tidset)::CharmRelation
    if tx == ty
        return EQUAL
    elseif issubset(tx, ty)
        return LEFT_SUBSET
    elseif issubset(ty, tx)
        return RIGHT_SUBSET
    else
        return INCOMPARABLE
    end
end

"""
    combine_nodes(x, y)

Create the candidate `X ∪ Y × (t(X) ∩ t(Y))` used by CHARM-Property.
"""
function combine_nodes(x::ITPair, y::ITPair)::ITPair
    return ITPair(union(x.items, y.items), intersect(x.tids, y.tids))
end

"""Result returned by [`charm_property`](@ref).

For an infrequent intersection, `frequent` is `false`, `relation` and
`candidate` are `nothing`, and the caller should prune the pair.  For a
frequent intersection, `candidate` is the combined IT-pair and `relation`
selects CHARM Property 1–4.  Applying the corresponding remove/merge/append
operation to an equivalence class remains the engine's responsibility.
"""
struct CharmPropertyResult
    frequent::Bool
    relation::Union{CharmRelation, Nothing}
    candidate::Union{ITPair, Nothing}
end

"""
    charm_property(x, y, minsup)

Evaluate the CHARM-Property operation for two IT-pairs:

1. Intersect their tidsets and prune when support is below `minsup`.
2. Classify the four CHARM relations (equal, left subset, right subset, or
   incomparable).
3. Return the union/intersection candidate for a frequent pair.

This function is deliberately side-effect free.  CHARM-Extend uses the
returned relation to mutate its current class: Properties 1 and 2 merge,
Property 3 removes the right node and queues the candidate, and Property 4
queues the candidate while retaining both nodes.
"""
function charm_property(x::ITPair, y::ITPair, minsup::Int)::CharmPropertyResult
    minsup >= 1 || throw(ArgumentError("minsup must be at least 1"))

    intersection = intersect(x.tids, y.tids)
    length(intersection) >= minsup ||
        return CharmPropertyResult(false, nothing, nothing)

    relation = classify_relation(x.tids, y.tids)
    candidate = ITPair(union(x.items, y.items), intersection)
    return CharmPropertyResult(true, relation, candidate)
end

end # module Properties
