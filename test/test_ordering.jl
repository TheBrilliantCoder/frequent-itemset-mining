using Test
using CharmMining

@testset "Itemset Ordering Tests" begin
    # Mock các cặp 2-itemset (F2)
    # pair 1: {"1", "2"} sup = 3
    # pair 2: {"2", "3"} sup = 2
    pairs = [
        ITPair(Itemset(["1", "2"]), BitSet([1, 2, 3])),
        ITPair(Itemset(["2", "3"]), BitSet([1, 2]))
    ]

    @testset "Build Weight Map" begin
        weight_map = CharmMining.Ordering.build_weight_map(pairs)
        @test weight_map["1"] == 3
        @test weight_map["2"] == 5
        @test weight_map["3"] == 2
        @test get(weight_map, "4", 0) == 0
    end

    @testset "CHARM Weight Calculation" begin
        weight_map = CharmMining.Ordering.build_weight_map(pairs)
        @test charm_weight("2", weight_map) == 5
        @test charm_weight("3", pairs) == 2
        @test charm_weight("nonexistent", weight_map) == 0
    end

    @testset "Order Itemsets by Ascending Weight" begin
        node1 = ITPair(Itemset(["1"]), BitSet([1, 2, 3]))
        node2 = ITPair(Itemset(["2"]), BitSet([1, 2, 3, 4, 5]))
        node3 = ITPair(Itemset(["3"]), BitSet([1, 2]))

        nodes = [node2, node1, node3]
        weight_map = CharmMining.Ordering.build_weight_map(pairs)
        sorted_nodes = order_itemsets_charm(nodes, weight_map)

        @test first(sorted_nodes[1].items) == "3"
        @test first(sorted_nodes[2].items) == "1"
        @test first(sorted_nodes[3].items) == "2"
    end
end