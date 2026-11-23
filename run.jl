include("src/CharmMining.jl")
using .CharmMining

input_file = "data/toy/test.txt"
output_file = "output.txt"
min_support = 10

println("Starting CHARM algorithm...")
results = mine_file(input_file; minsup=min_support, output_path=output_file)
println("Found $(length(results)) closed itemsets.")
