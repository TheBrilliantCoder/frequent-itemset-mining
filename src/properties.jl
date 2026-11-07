module Properties

using ..Models

export CharmRelation, EQUAL, LEFT_SUBSET, RIGHT_SUBSET, INCOMPARABLE,
       CharmPropertyResult, classify_relation, combine_nodes, charm_property

"""
    CharmRelation

Enum representing the four possible subset relations between two tidsets[cite: 2].
"""
@enum CharmRelation begin
    EQUAL          # t(X) == t(Y)
    LEFT_SUBSET    # t(X) ⊊ t(Y)
    RIGHT_SUBSET   # t(X) ⊋ t(Y)
    INCOMPARABLE   # neither tidset contains the other
end

"""
    classify_relation(tx, ty)

Determine the subset relation between tidsets `tx` and `ty`[cite: 2], using length
checks first to avoid unnecessary subset scans.
"""
function classify_relation(tx::Tidset, ty::Tidset)::CharmRelation
    if tx == ty
        return EQUAL
    elseif length(tx) < length(ty) && issubset(tx, ty)
        return LEFT_SUBSET
    elseif length(tx) > length(ty) && issubset(ty, tx)
        return RIGHT_SUBSET
    else
        return INCOMPARABLE
    end
end

"""
    combine_nodes(x, y)

Combine two `ITPair`s by taking the union of their items and the intersection
of their tidsets (`X ∪ Y × (t(X) ∩ t(Y))`)[cite: 2].
"""
function combine_nodes(x::ITPair, y::ITPair)::ITPair
    return ITPair(union(x.items, y.items), intersect(x.tids, y.tids))
end

"""
    CharmPropertyResult

Hold the outcome of `charm_property`: whether the combined pair is frequent,
its `CharmRelation` (Properties 1–4), and the resulting candidate `ITPair`[cite: 2].
"""
struct CharmPropertyResult
    frequent::Bool
    relation::Union{CharmRelation, Nothing}
    candidate::Union{ITPair, Nothing}
end

"""
    charm_property(x, y, minsup)

Intersect `x` and `y` tidsets, prune if support < `minsup`[cite: 2], and classify
their CHARM relation in O(1) time using precomputed tidset lengths.
"""
function charm_property(x::ITPair, y::ITPair, minsup::Int)::CharmPropertyResult
    minsup >= 1 || throw(ArgumentError("minsup must be at least 1"))

    intersection = intersect(x.tids, y.tids)
    len_int = length(intersection)
    len_int >= minsup || return CharmPropertyResult(false, nothing, nothing)

    len_x = length(x.tids)
    len_y = length(y.tids)

    relation = if len_int == len_x && len_int == len_y
        EQUAL
    elseif len_int == len_x
        LEFT_SUBSET
    elseif len_int == len_y
        RIGHT_SUBSET
    else
        INCOMPARABLE
    end

    candidate = ITPair(union(x.items, y.items), intersection)
    return CharmPropertyResult(true, relation, candidate)
end

end # module Properties
