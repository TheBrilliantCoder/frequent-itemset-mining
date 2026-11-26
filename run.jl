include("src/CharmMining.jl")
using .CharmMining

input_file = "data/toy/contextPasquier99.txt"
output_file = "results/output.txt"
min_support = 2  # Ngưỡng minsup dạng số lượng giao dịch (Int)

mkpath(dirname(output_file))
println("Starting CHARM algorithm (Optimized)...")
results = mine_file_bit(input_file; minsup = min_support, output_path = output_file)
println("Found $(length(results)) closed itemsets.")
