# src/optimized/models.jl

"""
    FastBitTidset
Biểu diễn Tidset bằng BitVector (BitArray 1 chiều), lưu kèm support (O(1))
và khóa băm 64-bit tính bằng tập lệnh вектор hóa @simd.
"""
struct FastBitTidset
    bits::BitVector
    supp::Int
    checksum::UInt64
end

@inline function calc_bit_checksum(chunks::Vector{UInt64})::UInt64
    h = UInt64(0)
    @inbounds @simd for i in eachindex(chunks)
        w = chunks[i]
        h = xor(h, w * UInt64(0x9e3779b97f4a7c15) + UInt64(i) * UInt64(0x517cc1b727220a95))
    end
    return h
end

FastBitTidset(bits::BitVector) = FastBitTidset(bits, count(bits), calc_bit_checksum(bits.chunks))

"""
    FastITNode
Đại diện cặp (Itemset, Tidset) đã tối ưu:
- `items`: Vector{Int32} luôn được duy trì theo thứ tự tăng dần.
- `tids`: FastBitTidset.
"""
struct FastITNode
    items::Vector{Int32}
    tids::FastBitTidset
end

@inline fast_support(node::FastITNode)::Int = node.tids.supp

"""
    BitVerticalDB
Cơ sở dữ liệu dọc lưu ánh xạ hai chiều Item (String) <-> ID (Int32)
và danh sách FastBitTidset của từng item.
"""
struct BitVerticalDB
    int_to_item::Vector{Item}
    tids::Vector{FastBitTidset}
    n_trans::Int
end

"""
Chuyển danh sách giao dịch sang BitVerticalDB, mã hóa Item theo đúng thứ tự từ điển.
"""
function to_vertical_bit(transactions::Vector{Vector{Item}})::BitVerticalDB
    n_trans = length(transactions)
    n_trans == 0 && return BitVerticalDB(Item[], FastBitTidset[], 0)

    unique_items = Set{Item}()
    for t in transactions, item in t
        push!(unique_items, item)
    end
    int_to_item = sort!(collect(unique_items))
    item_to_int = Dict{Item, Int32}(item => Int32(i) for (i, item) in enumerate(int_to_item))

    n_items = length(int_to_item)
    raw_bits = [falses(n_trans) for _ in 1:n_items]

    @inbounds for (tid, transaction) in enumerate(transactions)
        for item in transaction
            id = item_to_int[item]
            raw_bits[id][tid] = true
        end
    end

    tids = [FastBitTidset(bv) for bv in raw_bits]
    return BitVerticalDB(int_to_item, tids, n_trans)
end

"""
Hợp hai mảng Int32 đã sắp xếp trong thời gian tuyến tính O(|a| + |b|).
"""
function sorted_union(a::Vector{Int32}, b::Vector{Int32})::Vector{Int32}
    na, nb = length(a), length(b)
    res = Vector{Int32}(undef, na + nb)
    i = 1; j = 1; k = 0
    @inbounds while i <= na && j <= nb
        va, vb = a[i], b[j]
        if va < vb
            k += 1; res[k] = va; i += 1
        elseif va > vb
            k += 1; res[k] = vb; j += 1
        else
            k += 1; res[k] = va; i += 1; j += 1
        end
    end
    @inbounds while i <= na
        k += 1; res[k] = a[i]; i += 1
    end
    @inbounds while j <= nb
        k += 1; res[k] = b[j]; j += 1
    end
    resize!(res, k)
    return res
end

"""
Kiểm tra `a ⊆ b` trên hai mảng Int32 đã sắp xếp trong O(|a| + |b|) với 0 allocation.
"""
function sorted_issubset(a::Vector{Int32}, b::Vector{Int32})::Bool
    na, nb = length(a), length(b)
    na > nb && return false
    i = 1; j = 1
    @inbounds while i <= na && j <= nb
        va, vb = a[i], b[j]
        if va == vb
            i += 1; j += 1
        elseif va > vb
            j += 1
        else
            return false
        end
    end
    return i > na
end

Base.:(==)(a::ClosedItemset, b::ClosedItemset)::Bool =
    (a.support == b.support) && (a.items == b.items)