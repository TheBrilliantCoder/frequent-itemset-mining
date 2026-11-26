const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const DATA_DIR        = joinpath(REPOSITORY_ROOT, "data", "applications", "dna")
const RESULTS_DIR     = joinpath(REPOSITORY_ROOT, "results", "app2")

const CHARM_MODULE_PATH     = joinpath(REPOSITORY_ROOT, "src", "CharmMining.jl")
const DATASET_PATH          = joinpath(DATA_DIR, "human_preprocessed.txt")

# Đường dẫn cho Global Mining
const GLOBAL_TX_PATH        = joinpath(DATA_DIR, "transactions_global_k6.txt")
const GLOBAL_OUTPUT_PATH    = joinpath(RESULTS_DIR, "global_closed_itemsets_k6.txt")
const GLOBAL_K              = 6
const GLOBAL_MIN_SUP_RATIO  = 0.30

# Đường dẫn cho Per-Class Mining
const PER_CLASS_TX_DIR      = joinpath(DATA_DIR, "per_class_tx")
const PER_CLASS_OUTPUT_DIR  = joinpath(RESULTS_DIR, "per_class_charm")
const PER_CLASS_K           = 8
const PER_CLASS_MIN_SUP     = 0.15

const VALID_BASES = Set(['A', 'T', 'C', 'G'])

include(CHARM_MODULE_PATH)
using .CharmMining
using Printf

# Hàm hỗ trợ trích xuất k-mer từ một chuỗi DNA
function extract_kmers(seq::AbstractString, k::Int)::Set{Item}
    tokens = Set{Item}()
    for i in 1:(length(seq) - k + 1)
        kmer = SubString(seq, i, i + k - 1)
        all(c -> c in VALID_BASES, kmer) && push!(tokens, String(kmer))
    end
    return tokens
end

# 1. Chạy Global Mining (Toàn cục)
function run_global_mining()
    mkpath(dirname(GLOBAL_TX_PATH))
    mkpath(dirname(GLOBAL_OUTPUT_PATH))

    lines = readlines(DATASET_PATH)
    total_seqs = 0

    open(GLOBAL_TX_PATH, "w") do io
        for line in @view lines[2:end]
            parts = split(strip(line), '\t')
            length(parts) < 2 && continue
            seq, cls = uppercase(parts[1]), "CLASS_" * strip(parts[2])
            length(seq) < GLOBAL_K && continue

            tokens = extract_kmers(seq, GLOBAL_K)
            push!(tokens, cls)
            println(io, join(tokens, " "))
            total_seqs += 1
        end
    end

    minsup = ceil(Int, GLOBAL_MIN_SUP_RATIO * total_seqs)
    println("=== [GLOBAL MINING] k=$GLOBAL_K | Sequences=$total_seqs | minsup=$minsup ===")
    flush(stdout)

    @time begin
        transactions = load_transactions(GLOBAL_TX_PATH)
        db = to_vertical_bit(transactions)
        closed_itemsets = run_charm_bit(db, minsup)
        export_result(GLOBAL_OUTPUT_PATH; itemsets = closed_itemsets)
    end

    motif_patterns = filter(c -> any(it -> !startswith(it, "CLASS_"), c.items), closed_itemsets)
    println("Tổng số Global Closed Patterns: $(length(motif_patterns))\n")
end

# 2. Chạy Per-Class Mining (Tách riêng từng họ protein)
function run_per_class_mining()
    mkpath(PER_CLASS_TX_DIR)
    mkpath(PER_CLASS_OUTPUT_DIR)

    lines = readlines(DATASET_PATH)
    class_seqs = Dict{String, Vector{String}}()

    for line in @view lines[2:end]
        parts = split(strip(line), '\t')
        length(parts) < 2 && continue
        seq, cls = uppercase(parts[1]), "CLASS_" * strip(parts[2])
        length(seq) < PER_CLASS_K && continue
        push!(get!(Vector{String}, class_seqs, cls), seq)
    end

    println("=== [PER-CLASS MINING] k=$PER_CLASS_K | minsup_ratio=$(PER_CLASS_MIN_SUP * 100)% ===")
    flush(stdout)

    @time for cls in sort!(collect(keys(class_seqs)))
        seqs = class_seqs[cls]
        n_seqs = length(seqs)
        minsup = max(5, ceil(Int, PER_CLASS_MIN_SUP * n_seqs))

        tx_path  = joinpath(PER_CLASS_TX_DIR, "$(cls)_transactions.txt")
        out_path = joinpath(PER_CLASS_OUTPUT_DIR, "$(cls)_charm_output.txt")

        open(tx_path, "w") do io
            for seq in seqs
                tokens = extract_kmers(seq, PER_CLASS_K)
                println(io, join(tokens, " "))
            end
        end

        transactions = load_transactions(tx_path)
        db = to_vertical_bit(transactions)
        closed_itemsets = run_charm_bit(db, minsup)
        export_result(out_path; itemsets = closed_itemsets)

        sort!(closed_itemsets, by = c -> (length(c.items), c.support), rev = true)
        top_sample = isempty(closed_itemsets) ? "None" : join(closed_itemsets[1].items, "+")

        @printf("  %-7s | Seqs=%4d | minsup=%3d | Patterns=%4d | Top motif: %s\n",
                cls, n_seqs, minsup, length(closed_itemsets), top_sample)
        flush(stdout)
    end
end

function main()
    run_global_mining()
    run_per_class_mining()
end

main()