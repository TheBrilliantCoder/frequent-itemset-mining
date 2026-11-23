using Test
using CharmMining

@testset "CHARM Properties Tests" begin
    minsup = 2

    @testset "Property 1: EQUAL (T(X) == T(Y))" begin
        px = ITPair(Itemset(["1"]), BitSet([1, 2, 3]))
        py = ITPair(Itemset(["2"]), BitSet([1, 2, 3]))

        res = charm_property(px, py, minsup)
        @test res.frequent == true
        @test res.relation == EQUAL
        @test res.candidate.items == Itemset(["1", "2"])
        @test res.candidate.tids == BitSet([1, 2, 3])
    end

    @testset "Property 2: LEFT_SUBSET (T(X) ⊂ T(Y))" begin
        px = ITPair(Itemset(["1"]), BitSet([1, 2]))
        py = ITPair(Itemset(["2"]), BitSet([1, 2, 3, 4]))

        res = charm_property(px, py, minsup)
        @test res.frequent == true
        @test res.relation == LEFT_SUBSET
        @test res.candidate.items == Itemset(["1", "2"])
        @test res.candidate.tids == BitSet([1, 2])
    end

    @testset "Property 3: RIGHT_SUBSET (T(X) ⊃ T(Y))" begin
        px = ITPair(Itemset(["1"]), BitSet([1, 2, 3, 4]))
        py = ITPair(Itemset(["2"]), BitSet([1, 2]))

        res = charm_property(px, py, minsup)
        @test res.frequent == true
        @test res.relation == RIGHT_SUBSET
        @test res.candidate.items == Itemset(["1", "2"])
        @test res.candidate.tids == BitSet([1, 2])
    end

    @testset "Property 4: INCOMPARABLE (T(X) ≠ T(Y))" begin
        px = ITPair(Itemset(["1"]), BitSet([1, 2, 3]))
        py = ITPair(Itemset(["2"]), BitSet([2, 3, 4]))

        res = charm_property(px, py, minsup)
        @test res.frequent == true
        @test res.relation == INCOMPARABLE
        @test res.candidate.items == Itemset(["1", "2"])
        @test res.candidate.tids == BitSet([2, 3])
    end

    @testset "Infrequent Intersection Pruning & Invalid minsup" begin
        px = ITPair(Itemset(["1"]), BitSet([1, 2]))
        py = ITPair(Itemset(["2"]), BitSet([2, 3])) # Giao là BitSet([2]), sup = 1 < minsup (2)

        res = charm_property(px, py, minsup)
        @test res.frequent == false
        @test res.relation === nothing
        @test res.candidate === nothing

        @test_throws ArgumentError charm_property(px, py, 0)
    end
end
