# src/optimized/repository.jl

struct FastRepository
    buckets::Dict{Int, Dict{UInt64, Vector{FastITNode}}}
    FastRepository() = new(Dict{Int, Dict{UInt64, Vector{FastITNode}}}())
end

"""
Kiểm tra tính đóng trên bảng băm 2 tầng (Support -> 64-bit XOR Checksum)
sử dụng hàm sorted_issubset không cấp phát bộ nhớ.
"""
function consider_bit!(repo::FastRepository, candidate::FastITNode)::Bool
    supp = candidate.tids.supp
    chk = candidate.tids.checksum
    supp_map = get!(repo.buckets, supp) do
        Dict{UInt64, Vector{FastITNode}}()
    end
    bucket = get!(supp_map, chk) do
        FastITNode[]
    end

    c_items = candidate.items
    c_len = length(c_items)

    # 1. Bỏ qua nếu đã có tập cha cùng mức support chứa candidate
    @inbounds for existing in bucket
        if length(existing.items) >= c_len && sorted_issubset(c_items, existing.items)
            return false
        end
    end

    # 2. Xóa tại chỗ các tập con chặt bị candidate bao hàm
    idx = 1
    @inbounds while idx <= length(bucket)
        existing = bucket[idx]
        if length(existing.items) < c_len && sorted_issubset(existing.items, c_items)
            bucket[idx] = bucket[end]
            pop!(bucket)
        else
            idx += 1
        end
    end

    push!(bucket, candidate)
    return true
end

"""
Giải mã ID nguyên về chuỗi Item ban đầu và trả về danh sách ClosedItemset chuẩn.
"""
function results_bit(repo::FastRepository, int_to_item::Vector{Item})::Vector{ClosedItemset}
    all_nodes = FastITNode[]
    for supp_map in values(repo.buckets), bucket in values(supp_map)
        append!(all_nodes, bucket)
    end

    sort!(all_nodes, by = n -> (-n.tids.supp, n.items))
    return ClosedItemset[
        ClosedItemset(Item[int_to_item[id] for id in n.items], n.tids.supp)
        for n in all_nodes
    ]
end