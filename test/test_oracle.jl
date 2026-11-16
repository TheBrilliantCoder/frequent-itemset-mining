using Test
using CharmMining

function parse_spmf_file(filepath::String)
    res = Dict{Set{String}, Int}()
    for line in eachline(filepath)
        l = strip(line)
        isempty(l) && continue
        first(l) in ('#', '%', '@') && continue

        parts = split(l, "#SUP:")
        length(parts) == 2 || continue
        items = Set(String.(split(strip(parts[1]))))
        sup = parse(Int, strip(parts[2]))
        res[items] = sup
    end
    return res
end

@testset "SPMF Oracle Automated Verification" begin
    spmf_jar = joinpath(@__DIR__, "..", "tools", "spmf.jar")

    if !isfile(spmf_jar)
        @warn "tools/spmf.jar not found! Skipping SPMF Oracle comparative tests."
    else
        # 1. CSDL 1: Toy Dataset (contextPasquier99.txt) - 9 giao dịch
        toy_path = joinpath(@__DIR__, "..", "data", "toy", "contextPasquier99.txt")
        if isfile(toy_path)
            @info "Verifying with SPMF on Toy Dataset (contextPasquier99)..."
            out_julia     = tempname() * ".txt"
            out_julia_opt = tempname() * ".txt"
            out_spmf      = tempname() * ".txt"

            try
                mine_file(toy_path; minsup = 2, output_path = out_julia)
                mine_file_bit(toy_path; minsup = 2, output_path = out_julia_opt)
                run(`java -jar $spmf_jar run Charm_bitset $toy_path $out_spmf 22%`)

                julia_res     = parse_spmf_file(out_julia)
                julia_opt_res = parse_spmf_file(out_julia_opt)
                spmf_res      = parse_spmf_file(out_spmf)

                @test length(julia_res) == length(spmf_res)
                @test length(julia_opt_res) == length(spmf_res)

                for (itemset, sup) in spmf_res
                    @test haskey(julia_res, itemset)
                    @test julia_res[itemset] == sup
                    @test haskey(julia_opt_res, itemset)
                    @test julia_opt_res[itemset] == sup
                end
                @info "-> Toy Dataset: Passed 100% match (both Baseline & Optimized)."
            finally
                rm(out_julia, force = true)
                rm(out_julia_opt, force = true)
                rm(out_spmf, force = true)
            end
        end

        # 2. 5 CSDL Benchmark chuẩn FIMI / SPMF
        # Ngưỡng minsup được chọn tối ưu để test nhanh mà vẫn sinh đủ không gian mẫu đóng
        benchmark_dir = joinpath(@__DIR__, "..", "data", "benchmark")
        benchmark_tests = [
            ("mushroom.txt",   0.3,  "30%"),   # Dense, trung bình
            ("chess.txt",      0.7,  "70%"),   # Very Dense, itemset dài
            ("retail.txt",     0.02, "2%"),    # Very Sparse, thực tế (88k tx)
            ("T10I4D100K.txt", 0.02, "2%"),    # Sparse, tổng hợp (100k tx)
            ("accidents.txt",  0.8,  "80%")    # Very Large & Dense (340k tx)
        ]

        for (filename, ratio, spmf_arg) in benchmark_tests
            input_path = joinpath(benchmark_dir, filename)
            if !isfile(input_path)
                @warn "Benchmark file $filename not found in $benchmark_dir. Skipping."
                continue
            end

            @info "Verifying with SPMF on Benchmark: $filename (minsup = $spmf_arg)..."
            out_julia     = tempname() * ".txt"
            out_julia_opt = tempname() * ".txt"
            out_spmf      = tempname() * ".txt"

            try
                txs = load_transactions(input_path)
                minsup_count = ceil(Int, length(txs) * ratio)

                # Chạy cài đặt Julia (cả bản Cơ bản và bản Tối ưu)
                mine_file(input_path; minsup = minsup_count, output_path = out_julia)
                mine_file_bit(input_path; minsup = minsup_count, output_path = out_julia_opt)

                # Chạy SPMF đối chứng
                run(`java -jar $spmf_jar run Charm_bitset $input_path $out_spmf $spmf_arg`)

                julia_res     = parse_spmf_file(out_julia)
                julia_opt_res = parse_spmf_file(out_julia_opt)
                spmf_res      = parse_spmf_file(out_spmf)

                # So khớp tổng số lượng itemset đóng
                @test length(julia_res) == length(spmf_res)
                @test length(julia_opt_res) == length(spmf_res)

                # So khớp từng itemset và giá trị support tương ứng
                mismatches_basic = 0
                mismatches_opt   = 0
                for (itemset, sup) in spmf_res
                    if !haskey(julia_res, itemset) || julia_res[itemset] != sup
                        mismatches_basic += 1
                    end
                    if !haskey(julia_opt_res, itemset) || julia_opt_res[itemset] != sup
                        mismatches_opt += 1
                    end
                end

                @test mismatches_basic == 0
                @test mismatches_opt == 0
                @info "-> $filename: 100% match ($(length(spmf_res)) closed itemsets, Baseline & Optimized)."
            finally
                rm(out_julia, force = true)
                rm(out_julia_opt, force = true)
                rm(out_spmf, force = true)
            end
        end
    end
end