module Repository

using ..Models

export ClosedItemsetRepository, tid_checksum, consider!, results

"""
    ClosedItemsetRepository()

Two-level hash table storing closed itemsets, indexed by support and then by
TID sum checksum to enable fast subsumption checks[cite: 1].
"""
mutable struct ClosedItemsetRepository
    buckets::Dict{Int, Dict{UInt64, Vector{ITPair}}}

    ClosedItemsetRepository() = new(Dict{Int, Dict{UInt64, Vector{ITPair}}}())
end

"""
    tid_checksum(tids)

Compute the hash key for a tidset by summing all its transaction IDs
(`h(t(X)) = sum(tid)`)[cite: 1].
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

Perform fast subsumption check: insert `candidate` if no equal-support superset
exists in its checksum bucket, and prune any strict subsets it subsumes[cite: 1].
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

    # Skip if an existing itemset with equal support already contains candidate.
    for existing in bucket
        issubset(candidate.items, existing.items) && return false
    end

    # Remove older strict subsets with equal support before inserting candidate.
    filter!(existing -> !(
        issubset(existing.items, candidate.items) &&
        existing.items != candidate.items
    ), bucket)
    push!(bucket, candidate)
    return true
end

"""
    results(repo)

Extract all stored closed itemsets, sorted by decreasing support and then
lexicographically by item names[cite: 1].
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
