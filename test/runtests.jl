using Test

println("==================================================")
println("      RUNNING CHARMMINING AUTOMATED TESTS         ")
println("==================================================")

@testset "CharmMining.jl Full Test Suite" begin
    include("test_data.jl")
    include("test_ordering.jl")
    include("test_properties.jl")
    include("test_repository.jl")
    include("test_engine.jl")
    include("test_oracle.jl")
end

println("==================================================")
println("              ALL TESTS COMPLETED                 ")
println("==================================================")