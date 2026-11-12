using Test
using Dates

const BORDER  = repeat("=", 65)
const DIVIDER = repeat("-", 65)

println(BORDER)
println("           CHARMMINING.JL AUTOMATED TEST SUITE")
println(BORDER)
println(" Julia Version : $(VERSION)")
println(" Platform      : $(Sys.MACHINE)")
println(" Active Threads: $(Threads.nthreads())")
println(" Started At    : $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
println(BORDER)

total_start_time = time()

# Hàm hỗ trợ chạy và đo thời gian chi tiết từng file kiểm thử
function execute_test(title::String, filename::String)
    println("\n[RUNNING] $title ($filename)")
    t0 = time()
    try
        include(joinpath(@__DIR__, filename))
        elapsed = round(time() - t0, digits = 2)
        println("[PASSED]  $title (completed in $(elapsed)s)")
    catch err
        elapsed = round(time() - t0, digits = 2)
        println("[FAILED]  $title (halted after $(elapsed)s)")
        rethrow(err)
    end
end

@testset "CharmMining.jl Full Test Suite" begin
    execute_test("1. Data Loading & Preprocessing", "test_data.jl")
    execute_test("2. Itemset Ordering & Weights",   "test_ordering.jl")
    execute_test("3. CHARM Properties (1 to 4)",    "test_properties.jl")
    execute_test("4. Repository & Subsumption",      "test_repository.jl")
    execute_test("5. CHARM Engine Integration",     "test_engine.jl")
    execute_test("6. SPMF Oracle Cross-Validation", "test_oracle.jl")
end

total_elapsed = round(time() - total_start_time, digits = 2)

println("\n" * BORDER)
println(" ALL TESTS FINISHED COMPLETED IN $(total_elapsed)s")
println(BORDER)