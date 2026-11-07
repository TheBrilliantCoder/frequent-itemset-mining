module Ordering

using ..Models

export ordering_key, order_itemsets

"""
Khóa sắp xếp: support tăng dần; nếu hòa thì so sánh vector item đã sort theo từ điển.
"""
function ordering_key(node::ITPair)::Tuple{Int, Vector{Item}}
    return (support(node), sort!(collect(node.items)))
end

"""
Sắp xếp mảng ITPair theo quy tắc tất định, không làm biến đổi mảng đầu vào.
"""
function order_itemsets(nodes::Vector{ITPair})::Vector{ITPair}
    return sort(nodes, by = ordering_key)
end

end # module Ordering