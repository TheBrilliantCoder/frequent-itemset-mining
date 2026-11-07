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
    
    if output_path !== nothing
        open(output_path, "w") do io
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
Lọc các item có |tids| >= minsup và bọc vào ITPair.
Bắt buộc gọi trực tiếp `ordering_key` từ Người 2 để trả về danh sách được sắp xếp chuẩn.
`sort_fn` là khóa sắp xếp, mặc định dùng `ordering_key`.
"""
function frequent_singletons(
    db::VerticalDB, minsup::Int, sort_fn::Function = ordering_key
)::Vector{ITPair}
    nodes = ITPair[]
    for (item, tids) in db
        if length(tids) >= minsup
            push!(nodes, ITPair(Itemset([item]), copy(tids)))
        end
    end
    return sort!(nodes, by = sort_fn)
end

end # module Data
