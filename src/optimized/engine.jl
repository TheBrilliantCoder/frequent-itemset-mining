function charm_extend_bit(
    nodes::Vector{FastITNode},
    repo::FastRepository,
    minsup::Int,
    weights::Vector{Int}
)::Nothing
    n = length(nodes)
    removed = falses(n)

    @inbounds for i in 1:n
        removed[i] && continue
        x = nodes[i]
        child_nodes = FastITNode[]

        for j in (i + 1):n
            removed[j] && continue
            y = nodes[j]

            decision = charm_property_bit(x, y, minsup)
            decision.frequent || continue
            candidate = decision.candidate::FastITNode

            if decision.relation == EQUAL
                x = candidate
                removed[j] = true
                for k in eachindex(child_nodes)
                    c = child_nodes[k]
                    child_nodes[k] = FastITNode(sorted_union(c.items, y.items), c.tids)
                end
            elseif decision.relation == LEFT_SUBSET
                x = candidate
                for k in eachindex(child_nodes)
                    c = child_nodes[k]
                    child_nodes[k] = FastITNode(sorted_union(c.items, y.items), c.tids)
                end
            elseif decision.relation == RIGHT_SUBSET
                removed[j] = true
                push!(child_nodes, candidate)
            else
                push!(child_nodes, candidate)
            end
        end

        if !isempty(child_nodes)
            order_nodes_charm!(child_nodes, weights)
            charm_extend_bit(child_nodes, repo, minsup, weights)
        end

        consider_bit!(repo, x)
    end
    return nothing
end

function charm_bit(db::BitVerticalDB, minsup::Int)::Vector{ClosedItemset}
    minsup >= 1 || throw(ArgumentError("minsup must be at least 1"))
    db.n_trans == 0 && return ClosedItemset[]

    nodes = FastITNode[]
    @inbounds for (id, tids) in enumerate(db.tids)
        if tids.supp >= minsup
            push!(nodes, FastITNode(Int32[Int32(id)], tids))
        end
    end
    isempty(nodes) && return ClosedItemset[]

    weights = compute_f2_weights(nodes, length(db.int_to_item), minsup)
    order_nodes_charm!(nodes, weights)

    repo = FastRepository()
    charm_extend_bit(nodes, repo, minsup, weights)
    return results_bit(repo, db.int_to_item)
end

run_charm_bit(db::BitVerticalDB, minsup::Int)::Vector{ClosedItemset} = charm_bit(db, minsup)

function mine_file_bit(
    input_path::AbstractString;
    minsup::Int,
    output_path::Union{AbstractString, Nothing} = nothing,
    input_format::Symbol = :txt,
    output_format::Symbol = :txt
)::Vector{ClosedItemset}
    minsup >= 1 || throw(ArgumentError("minsup must be at least 1 transaction"))
    input_format === :txt || throw(ArgumentError("Unsupported input format: $input_format"))
    output_format === :txt || throw(ArgumentError("Unsupported output format: $output_format"))

    transactions = load_transactions(input_path; fmt = input_format)
    db = to_vertical_bit(transactions)
    itemsets = charm_bit(db, minsup)
    export_result(output_path; fmt = output_format, itemsets = itemsets)
    return itemsets
end