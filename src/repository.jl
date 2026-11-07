module Repository

using ..Models

export ClosedItemsetRepository, tid_checksum, consider!, results

"""
    ClosedItemsetRepository()

Hash-based repository for candidate closed itemsets.  The first bucket is the
candidate support and the second bucket is the arithmetic sum of its TIDs.
The vectors are intentional: different tidsets can have the same checksum,
so the final itemset subset check is always performed.
"""
mutable struct ClosedItemsetRepository
    buckets::Dict{Int, Dict{UInt64, Vector{ITPair}}}

    ClosedItemsetRepository() = new(Dict{Int, Dict{UInt64, Vector{ITPair}}}())
end

"""
    tid_checksum(tids)

Compute the hash key prescribed by `docs/charm.md`:

    h(t(X)) = sum(tid for tid in t(X))

The key is not the support/cardinality.  `UInt64` is used for the bucket key;
TIDs are non-negative Julia transaction indices, so conversion is safe.
"""
function tid_checksum(tids::Tidset)::UInt64
    total = UInt64(0)
    for tid in tids
        total += UInt64(tid)
    end
    return total
end

"""
    consider!(repo, candidate) -> Bool

Insert `candidate` unless an existing itemset is its superset with equal
support.  If inserted, remove older strict subsets with that same support so
the repository retains only closed representatives.

The checksum is only an index.  Equal support and itemset inclusion are
checked explicitly, making checksum collisions safe.
"""
function consider!(repo::ClosedItemsetRepository, candidate::ITPair)::Bool
    supp = support(candidate)
    checksum = tid_checksum(candidate.tids)
    support_buckets = get!(repo.buckets, supp) do
        Dict{UInt64, Vector{ITPair}}()
    end
    bucket = get!(support_buckets, checksum) do
        ITPair[]
    end

    # Existing equal-support superset means the candidate is not closed.
    for existing in bucket
        issubset(candidate.items, existing.items) && return false
    end

    # A newly discovered superset replaces strict subsets already stored in
    # this checksum bucket.  Keep unrelated itemsets and checksum collisions.
    filter!(existing -> !(
        issubset(existing.items, candidate.items) &&
        existing.items != candidate.items
    ), bucket)
    push!(bucket, candidate)
    return true
end

"""
    results(repo)

Return the repository contents as `ClosedItemset`s, ordered by decreasing
support and then lexicographically by sorted items.
"""
function results(repo::ClosedItemsetRepository)::Vector{ClosedItemset}
    nodes = ITPair[]
    for support_buckets in values(repo.buckets), bucket in values(support_buckets)
        append!(nodes, bucket)
    end

    sort!(nodes, by = node -> (-support(node), sort!(collect(node.items))))
    return ClosedItemset[
        ClosedItemset(sort!(collect(node.items)), support(node)) for node in nodes
    ]
end

end # module Repository
