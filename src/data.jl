module Data

using ..Models
using ..Ordering

export load_transactions, to_vertical, frequent_singletons, export_result

"""
Đọc file TXT trả về danh sách transaction.
TID tự động gán từ 1 đến N theo số dòng hợp lệ.
"""
function load_transactions(path::AbstractString; fmt::Symbol = :txt)::Vector{Vector{Item}} 

    transactions = Vector{Vector{Item}}()
    open(path, "r") do io
        for line in eachline(io)
            line = strip(line)

            isempty(line) && continue
            first(line) in ('#', '%', '@') && continue

            items = Item.(split(line))

            push!(transactions, sort!(unique!(items)))
        end
    end

    return transactions
end

"""
Nhận kết quả từ CHARM và tạo file TXT theo chuẩn SPMF.
"""
function export_result(path::Union{AbstractString, Nothing} = nothing;
    fmt::Symbol = :txt,
    itemsets::Vector{ClosedItemset})

    fmt === :txt || throw(ArgumentError("Unsupported output format: $fmt"))
    if path !== nothing
        open(path, "w") do io
            for itemset in itemsets
                println(io, join(itemset.items, " "), " #SUP: ", itemset.support)
            end
        end
    end
end
"""
Chuyển đổi danh sách transaction sang VerticalDB, dùng kiểu Tidset từ Models.
"""
function to_vertical(transactions::Vector{Vector{Item}})::VerticalDB 
    tidsets = VerticalDB()

    for (tid, transaction) in enumerate(transactions)
        for item in transaction
            push!(get!(Tidset, tidsets, item), Tid(tid))
        end
    end
    return tidsets
end

"""
Lọc các item có |tids| >= minsup và bọc vào ITPair, sau đó sắp xếp bằng
CHARM frequent-pair weight. Khi chưa có frequent pairs, tie-breakers vẫn giữ
kết quả tất định theo support và thứ tự từ điển.
"""
function frequent_singletons(
    db::VerticalDB, minsup::Int; frequent_pairs = ITPair[]
)::Vector{ITPair}
    nodes = ITPair[]
    for (item, tids) in db
        if length(tids) >= minsup
            push!(nodes, ITPair(Itemset([item]), copy(tids)))
        end
    end
    return order_itemsets_charm(nodes, frequent_pairs)
end

end # module Data
