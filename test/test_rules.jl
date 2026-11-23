using Test

if !isdefined(Main, :CharmMining)
    include(joinpath(@__DIR__, "..", "src", "CharmMining.jl"))
    using .CharmMining
end

@testset "Association Rules from Closed Frequent Itemsets" begin
    @testset "ClosureSupportIndex recovers exact support for non-closed subsets" begin
        # 5 transactions:
        # T1: A B C
        # T2: A B C
        # T3: A B
        # T4: B D
        # T5: D
        # Frequent closed itemsets (minsup = 2):
        # {B} (4), {A, B} (3), {A, B, C} (2), {D} (2)
        # Note: {A} is NOT closed (closure is {A, B}, supp = 3)
        #       {C} is NOT closed (closure is {A, B, C}, supp = 2)
        #       {A, C} is NOT closed (closure is {A, B, C}, supp = 2)
        txs = [
            ["A", "B", "C"],
            ["A", "B", "C"],
            ["A", "B"],
            ["B", "D"],
            ["D"],
        ]
        db = to_vertical_bit(txs)
        closed = charm_bit(db, 2)
        idx = build_support_index(closed)

        @test support_of(idx, ["B"]) == 4
        @test support_of(idx, ["A"]) == 3
        @test support_of(idx, ["C"]) == 2
        @test support_of(idx, ["A", "C"]) == 2
        @test support_of(idx, ["B", "C"]) == 2
        @test support_of(idx, ["A", "B"]) == 3
        @test support_of(idx, ["A", "B", "C"]) == 2
        @test support_of(idx, ["D"]) == 2
        @test_throws KeyError support_of(idx, ["A", "D"])
    end

    @testset "Exact Support, Confidence, Lift, Leverage, Conviction" begin
        txs = [
            ["A", "B", "C"],
            ["A", "B", "C"],
            ["A", "B"],
            ["B", "D"],
            ["D"],
        ]
        n_tx = length(txs)
        closed = charm_bit(to_vertical_bit(txs), 2)
        rules = generate_rules(closed, n_tx; minconf = 0.5, minlift = 1.0)

        # Check rule {A} => {B}: supp=3/5=0.6, conf=3/3=1.0, lift=1.0/(4/5)=1.25
        r_ab = only(filter(r -> r.antecedent == ["A"] && r.consequent == ["B"], rules))
        @test r_ab.support_count == 3
        @test isapprox(r_ab.support, 0.6; atol = 1e-12)
        @test isapprox(r_ab.confidence, 1.0; atol = 1e-12)
        @test isapprox(r_ab.lift, 1.25; atol = 1e-12)
        @test isapprox(r_ab.leverage, 0.6 - 0.6 * 0.8; atol = 1e-12)
        @test isinf(r_ab.conviction)

        # Check rule {C} => {A, B}: supp=2/5=0.4, conf=2/2=1.0, lift=1.0/(3/5)=5/3
        r_c_ab = only(filter(r -> r.antecedent == ["C"] && r.consequent == ["A", "B"], rules))
        @test r_c_ab.support_count == 2
        @test isapprox(r_c_ab.confidence, 1.0; atol = 1e-12)
        @test isapprox(r_c_ab.lift, 5.0 / 3.0; atol = 1e-12)

        # Verify ordering by descending lift
        for i in 1:(length(rules) - 1)
            @test rules[i].lift >= rules[i + 1].lift - 1e-12
        end
    end

    @testset "top_rules_by_lift and symmetric deduplication" begin
        txs = [
            ["1", "2", "5"],
            ["2", "4"],
            ["2", "3"],
            ["1", "2", "4"],
            ["1", "3"],
            ["2", "3"],
            ["1", "3"],
            ["1", "2", "3", "5"],
            ["1", "2", "3"],
        ]
        closed = charm_bit(to_vertical_bit(txs), 2)
        rules = generate_rules(closed, length(txs); minconf = 0.5, minlift = 1.0)
        @test !isempty(rules)

        top3 = top_rules_by_lift(rules, 3)
        @test length(top3) <= 3
        @test top3[1].lift >= top3[end].lift

        dedup = top_rules_by_lift(rules, 10; deduplicate_symmetric = true)
        seen = Set{Tuple{Vector{String}, Vector{String}}}()
        for r in dedup
            key = r.antecedent <= r.consequent ? (r.antecedent, r.consequent) : (r.consequent, r.antecedent)
            @test !(key in seen)
            push!(seen, key)
        end
    end
end
