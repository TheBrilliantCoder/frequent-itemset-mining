module Models

export Item, Tid, Itemset, Tidset, VerticalDB, ITPair, ClosedItemset, support

const Item = String
const Tid = Int
const Itemset = Set{Item}
const Tidset = BitSet           #TODO: basic: Set{Tid} Chuyển về data stucture basic roi so voi Bitset 
const VerticalDB = Dict{Item, Tidset}

"""
    ITPair(items, tids)
Đại diện cặp (Itemset, Tidset). Bất biến ngữ nghĩa.
"""
struct ITPair
    items::Itemset
    tids::Tidset

    function ITPair(items::Itemset, tids::Tidset)
        @assert !isempty(items) "Itemset không được rỗng"
        new(items, tids)
    end
end

support(node::ITPair)::Int = length(node.tids)

"""
    ClosedItemset(items, support)
Tập phổ biến đóng xuất ra pipeline. `items` luôn được sort tăng dần theo thứ tự từ điển.
"""
struct ClosedItemset
    items::Vector{Item}
    support::Int

    function ClosedItemset(items::Vector{Item}, supp::Int)
        @assert issorted(items) "items phải được sắp xếp từ điển"
        new(items, supp)
    end
end

end # module Models