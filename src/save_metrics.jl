using CharmMining
using Dates
using Printf
using Random

const BENCHMARK_DIR = joinpath(@__DIR__, "..", "data", "benchmark")
const RESULTS_DIR   = joinpath(@__DIR__, "..", "results")
mkpath(RESULTS_DIR)

# Cấu hình 5 tập dữ liệu chuẩn FIMI/SPMF và các ngưỡng minsup giảm dần (5-6 điểm/tập)
const DATASET_CONFIGS = [
    ("chess.txt",      [0.90, 0.85, 0.80, 0.75, 0.70, 0.65]),
    ("mushroom.txt",   [0.50, 0.45, 0.40, 0.35, 0.30, 0.25]),
    ("retail.txt",     [0.05, 0.04, 0.03, 0.02, 0.015, 0.01]),
    ("T10I4D100K.txt", [0.04, 0.03, 0.025, 0.02, 0.015, 0.01]),
    ("accidents.txt",  [0.90, 0.85, 0.80, 0.75, 0.70])
]

# Warm-up trình biên dịch JIT của Julia trước khi đo thật
function warmup_jit()
    println("[INFO] Đang chạy JIT Warm-up...")
    toy_txs = [
        ["1", "2", "3", "4"],
        ["1", "2", "4"],
        ["2", "3", "4"],
        ["1", "3"]
    ]
    db_b = to_vertical(toy_txs)
    db_o = to_vertical_bit(toy_txs)
    charm(db_b, 2)
    charm_bit(db_o, 2)
    GC.gc()
end

"""
1. Đo Execution Time, Memory Allocation và Number of Closed Itemsets
   qua các mức minsup giảm dần (Phục vụ Khải, Trúc, Lộc).
"""
function benchmark_minsup_sweep()
    out_csv = joinpath(RESULTS_DIR, "metrics_minsup.csv")
    println("\n=================================================================")
    println(" [1/3] ĐO METRICS THEO MINSUP -> $out_csv")
    println("=================================================================")

    open(out_csv, "w") do io
        println(io, "dataset,n_transactions,minsup_ratio,minsup_count,closed_count,baseline_time_s,optimized_time_s,speedup,baseline_mem_mb,optimized_mem_mb,mem_reduction_pct")

        for (filename, ratios) in DATASET_CONFIGS
            filepath = joinpath(BENCHMARK_DIR, filename)
            if !isfile(filepath)
                @warn "Không tìm thấy $filepath, bỏ qua."
                continue
            end

            println("\n>>> Đang nạp tập dữ liệu: $filename")
            txs = load_transactions(filepath)
            n_tx = length(txs)

            # Đo thời gian & RAM chuyển đổi sang Vertical DB
            GC.gc()
            t_conv_b = @timed to_vertical(txs)
            db_b = t_conv_b.value

            GC.gc()
            t_conv_o = @timed to_vertical_bit(txs)
            db_o = t_conv_o.value

            for r in ratios
                minsup = max(1, ceil(Int, n_tx * r))

                # Đo Baseline
                GC.gc()
                res_b = @timed charm(db_b, minsup)
                count_b = length(res_b.value)

                # Đo Optimized
                GC.gc()
                res_o = @timed charm_bit(db_o, minsup)
                count_o = length(res_o.value)

                @assert count_b == count_o "Sai lệch số lượng tập đóng trên $filename (minsup=$minsup)!"

                time_b = res_b.time
                time_o = res_o.time
                speedup = time_b / max(time_o, 1e-9)

                mem_b = res_b.bytes / (1024^2)
                mem_o = res_o.bytes / (1024^2)
                mem_red = (1.0 - (mem_o / max(mem_b, 1e-9))) * 100.0

                @printf("  minsup=%.3f (%6d) | Closed=%6d | Base=%.4fs (%.2fMB) | Opt=%.4fs (%.2fMB) | Speedup=%.2fx\n",
                        r, minsup, count_o, time_b, mem_b, time_o, mem_o, speedup)

                @printf(io, "%s,%d,%.4f,%d,%d,%.6f,%.6f,%.2f,%.4f,%.4f,%.2f\n",
                        filename, n_tx, r, minsup, count_o, time_b, time_o, speedup, mem_b, mem_o, mem_red)
                flush(io)
            end
        end
    end
end

"""
2. Đo Scalability theo kích thước CSDL: 10%, 25%, 50%, 75%, 100% (Phục vụ Lộc).
"""
function benchmark_scalability()
    out_csv = joinpath(RESULTS_DIR, "metrics_scalability.csv")
    println("\n=================================================================")
    println(" [2/3] ĐO SCALABILITY (10% -> 100%) -> $out_csv")
    println("=================================================================")

    scale_targets = [
        ("retail.txt",    0.015),
        ("accidents.txt", 0.75)
    ]
    fractions = [0.10, 0.25, 0.50, 0.75, 1.00]

    open(out_csv, "w") do io
        println(io, "dataset,sample_ratio,n_transactions,minsup_count,closed_count,baseline_time_s,optimized_time_s,speedup,baseline_mem_mb,optimized_mem_mb")

        for (filename, minsup_ratio) in scale_targets
            filepath = joinpath(BENCHMARK_DIR, filename)
            if !isfile(filepath)
                @warn "Không tìm thấy $filepath, bỏ qua."
                continue
            end

            full_txs = load_transactions(filepath)
            total_n = length(full_txs)
            println("\n>>> Scalability trên $filename (Tổng $total_n giao dịch, minsup_ratio = $minsup_ratio)")

            for frac in fractions
                sub_n = ceil(Int, total_n * frac)
                sub_txs = full_txs[1:sub_n]
                minsup = max(1, ceil(Int, sub_n * minsup_ratio))

                db_b = to_vertical(sub_txs)
                db_o = to_vertical_bit(sub_txs)

                GC.gc()
                res_b = @timed charm(db_b, minsup)

                GC.gc()
                res_o = @timed charm_bit(db_o, minsup)

                time_b = res_b.time
                time_o = res_o.time
                speedup = time_b / max(time_o, 1e-9)
                mem_b = res_b.bytes / (1024^2)
                mem_o = res_o.bytes / (1024^2)
                closed_cnt = length(res_o.value)

                @printf("  Scale=%3.0f%% (%6d txs) | Closed=%5d | Base=%.4fs (%.2fMB) | Opt=%.4fs (%.2fMB) | Speedup=%.2fx\n",
                        frac * 100, sub_n, closed_cnt, time_b, mem_b, time_o, mem_o, speedup)

                @printf(io, "%s,%.2f,%d,%d,%d,%.6f,%.6f,%.2f,%.4f,%.4f\n",
                        filename, frac, sub_n, minsup, closed_cnt, time_b, time_o, speedup, mem_b, mem_o)
                flush(io)
            end
        end
    end
end

"""
3. Đo ảnh hưởng của độ dài giao dịch trung bình trên CSDL tổng hợp
   (Chứng minh ưu thế của BitVector: độ phức tạp phép giao không phụ thuộc chiều rộng giao dịch).
"""
function benchmark_transaction_length()
    out_csv = joinpath(RESULTS_DIR, "metrics_tx_length.csv")
    println("\n=================================================================")
    println(" [3/3] ĐO ẢNH HƯỞNG ĐỘ DÀI GIAO DỊCH TRUNG BÌNH -> $out_csv")
    println("=================================================================")

    rng = MersenneTwister(42)
    n_tx = 10_000
    n_items = 80
    lengths = [10, 20, 30, 40, 50]

    open(out_csv, "w") do io
        println(io, "n_transactions,n_items,avg_tx_length,minsup_count,closed_count,baseline_time_s,optimized_time_s,speedup,baseline_mem_mb,optimized_mem_mb")

        for avg_len in lengths
            # Sinh dữ liệu tổng hợp với độ dài giao dịch trung bình = avg_len
            txs = Vector{Vector{Item}}(undef, n_tx)
            for i in 1:n_tx
                k = clamp(avg_len + rand(rng, -2:2), 1, n_items)
                chosen = randperm(rng, n_items)[1:k]
                txs[i] = sort!(String[string(x) for x in chosen])
            end

            # Cố định ngưỡng support tương đối theo mật độ để giữ không gian tìm kiếm ổn định
            minsup = ceil(Int, n_tx * (avg_len / n_items)^2 * 1.5)
            minsup = max(minsup, 50)

            db_b = to_vertical(txs)
            db_o = to_vertical_bit(txs)

            GC.gc()
            res_b = @timed charm(db_b, minsup)

            GC.gc()
            res_o = @timed charm_bit(db_o, minsup)

            time_b = res_b.time
            time_o = res_o.time
            speedup = time_b / max(time_o, 1e-9)
            mem_b = res_b.bytes / (1024^2)
            mem_o = res_o.bytes / (1024^2)
            closed_cnt = length(res_o.value)

            @printf("  AvgLen=%2d | minsup=%4d | Closed=%5d | Base=%.4fs (%.2fMB) | Opt=%.4fs (%.2fMB) | Speedup=%.2fx\n",
                    avg_len, minsup, closed_cnt, time_b, mem_b, time_o, mem_o, speedup)

            @printf(io, "%d,%d,%d,%d,%d,%.6f,%.6f,%.2f,%.4f,%.4f\n",
                    n_tx, n_items, avg_len, minsup, closed_cnt, time_b, time_o, speedup, mem_b, mem_o)
            flush(io)
        end
    end
end

function main()
    warmup_jit()
    benchmark_minsup_sweep()
    benchmark_scalability()
    benchmark_transaction_length()
    println("\n[DONE] Toàn bộ metrics đã được lưu vào thư mục: $RESULTS_DIR")
end

main()