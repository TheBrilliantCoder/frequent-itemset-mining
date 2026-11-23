module Properties

using ..Models

export CharmRelation, EQUAL, LEFT_SUBSET, RIGHT_SUBSET, INCOMPARABLE,
       CharmPropertyResult, charm_property

"""
    CharmRelation

Enum representing the four possible subset relations between two tidsets.
"""
@enum CharmRelation begin
    EQUAL          # t(X) == t(Y)
    LEFT_SUBSET    # t(X) ⊊ t(Y)
    RIGHT_SUBSET   # t(X) ⊋ t(Y)
    INCOMPARABLE   # neither tidset contains the other
end

"""
    CharmPropertyResult

Hold the outcome of `charm_property`: whether the combined pair is frequent,
its `CharmRelation` (Properties 1–4), and the resulting candidate `ITPair`.
"""
struct CharmPropertyResult
    frequent::Bool
    relation::Union{CharmRelation, Nothing}
    candidate::Union{ITPair, Nothing}
end

"""
    charm_property(x, y, minsup)

Intersect `x` and `y` tidsets, prune if support < `minsup`, and classify
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
