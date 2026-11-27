const REPOSITORY_ROOT   = normpath(joinpath(@__DIR__, "..", ".."))
const CHARM_MODULE_PATH = joinpath(REPOSITORY_ROOT, "src", "CharmMining.jl")
const DATASET_PATH      = joinpath(REPOSITORY_ROOT, "data", "applications", "dna", "promoters.data")
const RESULTS_DIR       = joinpath(REPOSITORY_ROOT, "results", "app2")
const OUTPUT_PATH       = joinpath(RESULTS_DIR, "promoters_charm_output.txt")

# Tham số khai phá de novo dựa trên các cụm điểm nóng 
const MIN_SUPPORT    = 5      # ~9.4% của 53 mẫu mỗi lớp, đủ nhạy để bắt các biến thể 5-mer
const K_MER_SIZE     = 5      # Phù hợp với độ dài cụm ngắn nhất C2 (8 bp) và lõi motif 5-6 bp
const VALID_BASES    = Set(['a', 'c', 'g', 't'])
const CLUSTER_RANGES = [("C1", 3:23), ("C2", 27:34), ("C3", 35:52)]

include(CHARM_MODULE_PATH)
using .CharmMining
using Printf

"""
Parse một dòng dữ liệu UCI promoter, trích xuất nhãn lớp và các k-mer trượt
bên trong từng cụm tọa độ từ CLUSTER_RANGES
"""
function parse_promoter_record(line::AbstractString)::Union{Nothing, Vector{String}}
    fields = split(strip(line), ',')
    length(fields) >= 3 || return nothing

    class = strip(fields[1])
    class in ("+", "-") || return nothing

    sequence = lowercase(strip(join(fields[3:end], ",")))
    sequence = filter(!isspace, sequence)
    length(sequence) == 57 || return nothing
    all(base -> base in VALID_BASES, sequence) || return nothing

    items = Set{String}(["class=$class"])
    for (cluster_name, range) in CLUSTER_RANGES
        start_idx = first(range)
        end_idx   = last(range) - K_MER_SIZE + 1
        for i in start_idx:end_idx
            kmer = sequence[i:(i + K_MER_SIZE - 1)]
            push!(items, "$(cluster_name)_$(kmer)")
        end
    end

    return sort!(collect(items))
end

"""
Chạy thuật toán CHARM và thống kê tách biệt số lượng tập đóng theo từng lớp
"""
function run_promoter_mining()
    isfile(DATASET_PATH) || error("Promoter dataset not found: $DATASET_PATH")
    transactions = Vector{Vector{String}}()
    skipped = 0

    for line in eachline(DATASET_PATH)
        record = parse_promoter_record(line)
        if record === nothing
            skipped += 1
        else
            push!(transactions, record)
        end
    end

    isempty(transactions) && error("No valid promoter records found in $DATASET_PATH")
    minsup = min(MIN_SUPPORT, length(transactions))

    println("=== E. coli De Novo Promoter Mining (CharmBit | k=$K_MER_SIZE) ===")
    @printf("Records=%d | skipped=%d | clusters=%d | minsup=%d\n",
            length(transactions), skipped, length(CLUSTER_RANGES), minsup)

    db = to_vertical_bit(transactions)
    closed_itemsets = run_charm_bit(db, minsup)

    mkpath(dirname(OUTPUT_PATH))
    export_result(OUTPUT_PATH; itemsets = closed_itemsets)

    pos_patterns = filter(p -> "class=+" in p.items, closed_itemsets)
    neg_patterns = filter(p -> "class=-" in p.items, closed_itemsets)

    @printf("Total Closed Patterns = %d | class=+ patterns = %d | class=- patterns = %d\n",
            length(closed_itemsets), length(pos_patterns), length(neg_patterns))
    println("Results written to $OUTPUT_PATH")
    return closed_itemsets
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_promoter_mining()
end