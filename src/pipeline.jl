module Pipeline

using ..Models
using ..Data
using ..Engine

export mine_file

"""
    mine_file(input_path; minsup, algorithm, output_path=nothing,
              input_format=:txt, output_format=:txt)

Pipeline: đọc TXT -> VerticalDB -> algorithm -> TXT theo định dạng SPMF.
Mỗi dòng đầu ra có dạng `1 2 #SUP: 3` (support là số transaction).
Trả về kết quả thuật toán và ghi TXT nếu có `output_path`.
Giữ nguyên thứ tự itemset và thứ tự từ điển của items theo Models.
"""
function mine_file(
    input_path::AbstractString;
    minsup::Int,
    algorithm::Function = run_charm,
    input_format::Symbol = :txt,
    output_path::Union{AbstractString, Nothing} = nothing,
    output_format::Symbol = :txt
)::Vector{ClosedItemset}

    minsup >= 1 || throw(ArgumentError("minsup must be at least 1 transaction"))
    input_format === :txt || throw(ArgumentError("Unsupported input format: $input_format"))
    output_format === :txt || throw(ArgumentError("Unsupported output format: $output_format"))

    transactions = load_transactions(input_path; fmt = input_format)
    db = to_vertical(transactions)
    itemsets = algorithm(db, minsup)::Vector{ClosedItemset}

    export_result(output_path; fmt = output_format, itemsets = itemsets)

    return itemsets
end

end # module Pipeline
