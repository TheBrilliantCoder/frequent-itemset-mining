# src/optimized/properties.jl

struct FastPropertyResult
    frequent::Bool
    relation::Union{CharmRelation, Nothing}
    candidate::Union{FastITNode, Nothing}
end

"""
Kiểm tra tính phổ biến của X ∪ Y bằng phép đếm bit @simd trước khi cấp phát bộ nhớ,
và tái sử dụng tham chiếu FastBitTidset cho các Property 1, 2, 3.
"""
function charm_property_bit(x::FastITNode, y::FastITNode, minsup::Int)::FastPropertyResult
    minsup >= 1 || throw(ArgumentError("minsup must be at least 1"))

    tx, ty = x.tids, y.tids
    ca, cb = tx.bits.chunks, ty.bits.chunks
    n_chunks = min(length(ca), length(cb))
    len_int = 0
    @inbounds @simd for k in 1:n_chunks
        len_int += count_ones(ca[k] & cb[k])
    end

    len_int < minsup && return FastPropertyResult(false, nothing, nothing)

    len_x, len_y = tx.supp, ty.supp
    merged_items = sorted_union(x.items, y.items)

    if len_int == len_x && len_int == len_y
        # Property 1
        return FastPropertyResult(true, EQUAL, FastITNode(merged_items, tx))
    elseif len_int == len_x
        # Property 2
        return FastPropertyResult(true, LEFT_SUBSET, FastITNode(merged_items, tx))
    elseif len_int == len_y
        # Property 3
        return FastPropertyResult(true, RIGHT_SUBSET, FastITNode(merged_items, ty))
    else
        # Property 4 (INCOMPARABLE)
        res_bits = BitVector(undef, length(tx.bits))
        cr = res_bits.chunks
        h = UInt64(0)
        @inbounds for k in 1:n_chunks
            w = ca[k] & cb[k]
            cr[k] = w
            h = xor(h, w * UInt64(0x9e3779b97f4a7c15) + UInt64(k) * UInt64(0x517cc1b727220a95))
        end
        int_tids = FastBitTidset(res_bits, len_int, h)
        return FastPropertyResult(true, INCOMPARABLE, FastITNode(merged_items, int_tids))
    end
end