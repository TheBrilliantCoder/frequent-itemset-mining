"""
Chapter 3 - Application 1: Market Basket Analysis using CharmMining (Optimized CHARM).

Runs our scratch Julia implementation (`mine_file_bit` + closure-based `generate_rules`)
on the cleaned UCI Online Retail dataset, performs minsup sensitivity analysis, and
extracts the Top-10 Association Rules ranked by Lift.

Usage:
    julia --project=. applications/market_basket/run_mba.jl
"""

using Printf

include(joinpath(@__DIR__, "..", "..", "src", "CharmMining.jl"))
using .CharmMining

struct ProductInfo
    stock_code::String
    description::String
    tx_count::Int
end

"""
Parse a CSV line handling quoted fields with commas.
"""
function parse_csv_line(line::AbstractString)::Vector{String}
    fields = String[]
    buf = IOBuffer()
    in_quotes = false
    i = firstindex(line)
    while i <= lastindex(line)
        c = line[i]
        if c == '"'
            if in_quotes && i < lastindex(line) && line[nextind(line, i)] == '"'
                write(buf, '"')
                i = nextind(line, i)
            else
                in_quotes = !in_quotes
            end
        elseif c == ',' && !in_quotes
            push!(fields, String(take!(buf)))
        else
            write(buf, c)
        end
        i = nextind(line, i)
    end
    push!(fields, String(take!(buf)))
    return fields
end

function csv_escape(s::AbstractString)::String
    if occursin(',', s) || occursin('"', s) || occursin('\n', s)
        return "\"" * replace(s, "\"" => "\"\"") * "\""
    end
    return String(s)
end

function load_item_mapping(path::AbstractString)::Dict{String, ProductInfo}
    mapping = Dict{String, ProductInfo}()
    open(path, "r") do io
        header = readline(io)
        for line in eachline(io)
            isempty(strip(line)) && continue
            cols = parse_csv_line(line)
            item_id = cols[1]
            stock_code = cols[2]
            desc = cols[3]
            tx_cnt = parse(Int, cols[4])
            mapping[item_id] = ProductInfo(stock_code, desc, tx_cnt)
        end
    end
    return mapping
end

function decode_items(items::Vector{String}, mapping::Dict{String, ProductInfo})::String
    names = [haskey(mapping, id) ? mapping[id].description : id for id in items]
    return join(names, " + ")
end

function decode_codes(items::Vector{String}, mapping::Dict{String, ProductInfo})::String
    codes = [haskey(mapping, id) ? mapping[id].stock_code : id for id in items]
    return join(codes, " + ")
end

function write_rules_csv(path::AbstractString, rules::Vector{AssociationRule}, mapping::Dict{String, ProductInfo})
    open(path, "w") do io
        println(io, "rank,antecedent_ids,consequent_ids,antecedent_codes,consequent_codes,antecedent_names,consequent_names,support_count,support_pct,confidence_pct,lift,leverage,conviction")
        for (rank, r) in enumerate(rules)
            conv_str = isinf(r.conviction) ? "Inf" : @sprintf("%.4f", r.conviction)
            println(
                io,
                rank, ",",
                csv_escape(join(r.antecedent, " ")), ",",
                csv_escape(join(r.consequent, " ")), ",",
                csv_escape(decode_codes(r.antecedent, mapping)), ",",
                csv_escape(decode_codes(r.consequent, mapping)), ",",
                csv_escape(decode_items(r.antecedent, mapping)), ",",
                csv_escape(decode_items(r.consequent, mapping)), ",",
                r.support_count, ",",
                @sprintf("%.4f", r.support * 100.0), ",",
                @sprintf("%.2f", r.confidence * 100.0), ",",
                @sprintf("%.4f", r.lift), ",",
                @sprintf("%.6f", r.leverage), ",",
                conv_str
            )
        end
    end
end

function main()
    repo_root = normpath(joinpath(@__DIR__, "..", ".."))
    data_dir = joinpath(repo_root, "data", "applications", "online_retail")
    results_dir = joinpath(repo_root, "results", "app1")
    mkpath(results_dir)

    tx_path = joinpath(data_dir, "transactions.txt")
    mapping_path = joinpath(data_dir, "item_mapping.csv")

    isfile(tx_path) || error("Missing $tx_path. Run `python applications/market_basket/prepare_data.py` first.")
    isfile(mapping_path) || error("Missing $mapping_path. Run `python applications/market_basket/prepare_data.py` first.")

    println("Loading transactions and product mapping...")
    transactions = load_transactions(tx_path)
    n_tx = length(transactions)
    mapping = load_item_mapping(mapping_path)
    db = to_vertical_bit(transactions)

    println("Loaded $(n_tx) transactions, $(length(db.int_to_item)) unique items.")

    # Warm-up JIT compilation
    _ = charm_bit(db, ceil(Int, 0.05 * n_tx))

    # 1. Minsup sensitivity analysis
    minsup_grid = [0.05, 0.03, 0.025, 0.02, 0.015, 0.01, 0.008]
    sens_path = joinpath(results_dir, "minsup_sensitivity.csv")
    println("\n=== 1. Minsup Sensitivity Analysis (Optimized CHARM) ===")
    println(@sprintf("%-10s %-10s %-12s %-10s %-12s %-12s", "minsup(%)", "minsup(#)", "Closed(#)", "MaxLen", "Rules(c>=50%)", "Time(ms)"))

    open(sens_path, "w") do io
        println(io, "minsup_pct,minsup_count,num_closed_itemsets,num_closed_len2plus,max_itemset_len,num_rules_conf50,runtime_ms")
        for ms_pct in minsup_grid
            ms_cnt = ceil(Int, ms_pct * n_tx)
            t0 = time_ns()
            closed = charm_bit(db, ms_cnt)
            elapsed_ms = (time_ns() - t0) / 1e6

            len2plus = count(c -> length(c.items) >= 2, closed)
            max_len = isempty(closed) ? 0 : maximum(length(c.items) for c in closed)
            rules = generate_rules(closed, n_tx; minconf = 0.50, minlift = 1.0)

            println(@sprintf("%-10.2f %-10d %-12d %-10d %-12d %-12.2f",
                ms_pct * 100.0, ms_cnt, length(closed), max_len, length(rules), elapsed_ms))
            println(io, @sprintf("%.2f,%d,%d,%d,%d,%d,%.3f",
                ms_pct * 100.0, ms_cnt, length(closed), len2plus, max_len, length(rules), elapsed_ms))
        end
    end

    # 2. Primary Market Basket Analysis (minsup = 1.0%, minconf = 50%, minlift > 1.0)
    primary_minsup_pct = 0.01
    primary_minsup_cnt = ceil(Int, primary_minsup_pct * n_tx)
    primary_minconf = 0.50
    primary_minlift = 1.0

    println("\n=== 2. Primary Mining (minsup = $(primary_minsup_pct * 100)% = $(primary_minsup_cnt) txs, minconf = $(primary_minconf * 100)%) ===")
    closed_out_path = joinpath(results_dir, "closed_itemsets_minsup1pct.txt")
    t0 = time_ns()
    closed_primary = mine_file_bit(tx_path; minsup = primary_minsup_cnt, output_path = closed_out_path)
    elapsed_ms = (time_ns() - t0) / 1e6

    multi_closed = sort(
        filter(c -> length(c.items) >= 2, closed_primary);
        by = c -> (-c.support, -length(c.items), c.items)
    )
    println("Found $(length(closed_primary)) closed itemsets ($(length(multi_closed)) with size >= 2) in $(round(elapsed_ms, digits=2)) ms.")

    # Export top closed itemsets (size >= 2) with product names
    top_closed_path = joinpath(results_dir, "top_closed_itemsets.csv")
    open(top_closed_path, "w") do io
        println(io, "rank,size,item_ids,stock_codes,product_names,support_count,support_pct")
        for (rank, c) in enumerate(multi_closed)
            println(
                io,
                rank, ",",
                length(c.items), ",",
                csv_escape(join(c.items, " ")), ",",
                csv_escape(decode_codes(c.items, mapping)), ",",
                csv_escape(decode_items(c.items, mapping)), ",",
                c.support, ",",
                @sprintf("%.4f", 100.0 * c.support / n_tx)
            )
        end
    end

    # Generate association rules
    all_rules = generate_rules(closed_primary, n_tx; minconf = primary_minconf, minlift = primary_minlift)
    println("Generated $(length(all_rules)) association rules (minconf=$(primary_minconf), minlift>=$(primary_minlift)).")

    all_rules_path = joinpath(results_dir, "all_rules.csv")
    write_rules_csv(all_rules_path, all_rules, mapping)

    # Top-10 rules by Lift (all rules & symmetric-deduplicated)
    top10_raw = top_rules_by_lift(all_rules, 10; deduplicate_symmetric = false)
    top10_dedup = top_rules_by_lift(all_rules, 10; deduplicate_symmetric = true)

    write_rules_csv(joinpath(results_dir, "top10_rules_lift_raw.csv"), top10_raw, mapping)
    write_rules_csv(joinpath(results_dir, "top10_rules_lift_dedup.csv"), top10_dedup, mapping)

    println("\n=== Top-10 Association Rules by Lift (Deduplicated Symmetric Pairs) ===")
    for (i, r) in enumerate(top10_dedup)
        ant = decode_items(r.antecedent, mapping)
        con = decode_items(r.consequent, mapping)
        println(@sprintf("%2d. [%s] => [%s]", i, ant, con))
        println(@sprintf("    Support: %.2f%% (%d txs) | Confidence: %.2f%% | Lift: %.2f | Leverage: %.4f",
            r.support * 100.0, r.support_count, r.confidence * 100.0, r.lift, r.leverage))
    end

    println("\nSaved all outputs to: $(results_dir)")
end

main()
