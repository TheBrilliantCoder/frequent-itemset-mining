# src/optimized/ordering.jl

"""
Tính tổng support của các cặp 2-itemset phổ biến (F₂) trực tiếp trên thanh ghi 64-bit
bằng @simd và count_ones mà không cấp phát BitVector trung gian.
"""
function compute_f2_weights(nodes::Vector{FastITNode}, n_items::Int, minsup::Int)::Vector{Int}
    weights = zeros(Int, n_items)
    n = length(nodes)
    @inbounds for i in 1:(n - 1)
        ca = nodes[i].tids.bits.chunks
        id_i = nodes[i].items[1]
        for j in (i + 1):n
            cb = nodes[j].tids.bits.chunks
            n_chunks = min(length(ca), length(cb))
            supp = 0
            @simd for k in 1:n_chunks
                supp += count_ones(ca[k] & cb[k])
            end
            if supp >= minsup
                id_j = nodes[j].items[1]
                weights[id_i] += supp
                weights[id_j] += supp
            end
        end
    end
    return weights
end

@inline function node_charm_weight(node::FastITNode, weights::Vector{Int})::Int
    w = 0
    @inbounds for id in node.items
        w += weights[id]
    end
    return w
end

"""
Sắp xếp tại chỗ danh sách FastITNode theo đúng thứ tự CHARM:
(tổng trọng số F₂, support, thứ tự từ điển).
"""
function order_nodes_charm!(nodes::Vector{FastITNode}, weights::Vector{Int})
    sort!(nodes, by = n -> (node_charm_weight(n, weights), n.tids.supp, n.items))
    return nodes
end