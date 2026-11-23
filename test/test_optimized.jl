using Test
using CharmMining

@testset "Optimized CHARM (BitVector + Int32 + SIMD) Full Suite" begin

    @testset "1. Optimized Models & Vertical Conversion" begin
        transactions = [
            ["1", "2", "5"],
            ["2", "4"],
            ["2", "3"],
            ["1", "2", "4"]
        ]
        vdb_bit = to_vertical_bit(transactions)

        @test vdb_bit isa BitVerticalDB
        @test vdb_bit.n_trans == 4
        @test vdb_bit.int_to_item == ["1", "2", "3", "4", "5"]

        # Kiểm tra BitVector và support được tính sẵn
        @test vdb_bit.tids[1].bits == BitVector([1, 0, 0, 1]) # item "1"
        @test vdb_bit.tids[1].supp == 2
        @test vdb_bit.tids[2].bits == BitVector([1, 1, 1, 1]) # item "2"
        @test vdb_bit.tids[2].supp == 4

        # Kiểm tra sorted_union và sorted_issubset (Zero-allocation set ops)
        a = Int32[1, 3, 5]
        b = Int32[2, 3, 6]
        @test sorted_union(a, b) == Int32[1, 2, 3, 5, 6]
        @test sorted_issubset(Int32[1, 5], a) == true
        @test sorted_issubset(Int32[1, 4], a) == false
        @test sorted_issubset(Int32[1, 2, 3, 4], a) == false
    end

    @testset "2. Optimized F2 Weight Calculation & Ordering" begin
        # Tương đương kịch bản trong test_ordering.jl:
        # item 1: [1, 2, 3] (sup 3)
        # item 2: [1, 2, 3, 4, 5] (sup 5)
        # item 3: [1, 2] (sup 2)
        node1 = FastITNode(Int32[1], FastBitTidset(BitVector([1, 1, 1, 0, 0])))
        node2 = FastITNode(Int32[2], FastBitTidset(BitVector([1, 1, 1, 1, 1])))
        node3 = FastITNode(Int32[3], FastBitTidset(BitVector([1, 1, 0, 0, 0])))

        nodes = [node2, node1, node3]
        # Với minsup = 2:
        # Cặp (1,2) sup=3, (1,3) sup=2, (2,3) sup=2
        # Trọng số: w(3) = 2+2 = 4, w(1) = 3+2 = 5, w(2) = 3+2 = 5
        weights = compute_f2_weights(nodes, 3, 2)
        @test weights[3] == 4
        @test weights[1] == 5
        @test weights[2] == 5

        order_nodes_charm!(nodes, weights)
        @test nodes[1].items == Int32[3]
        @test nodes[2].items == Int32[1] # Cùng w=5 với item 2 nhưng sup=3 < sup=5
        @test nodes[3].items == Int32[2]
    end

    @testset "3. Optimized CHARM Properties (1 to 4) & Memory Reuse" begin
        minsup = 2

        @testset "Property 1: EQUAL (T(X) == T(Y)) & Zero-Alloc Reuse" begin
            px = FastITNode(Int32[1], FastBitTidset(BitVector([1, 1, 1, 0])))
            py = FastITNode(Int32[2], FastBitTidset(BitVector([1, 1, 1, 0])))

            res = charm_property_bit(px, py, minsup)
            @test res.frequent == true
            @test res.relation == EQUAL
            @test res.candidate.items == Int32[1, 2]
            @test res.candidate.tids === px.tids # Tái sử dụng trực tiếp vùng nhớ tx
        end

        @testset "Property 2: LEFT_SUBSET (T(X) ⊂ T(Y))" begin
            px = FastITNode(Int32[1], FastBitTidset(BitVector([1, 1, 0, 0])))
            py = FastITNode(Int32[2], FastBitTidset(BitVector([1, 1, 1, 1])))

            res = charm_property_bit(px, py, minsup)
            @test res.frequent == true
            @test res.relation == LEFT_SUBSET
            @test res.candidate.items == Int32[1, 2]
            @test res.candidate.tids === px.tids
        end

        @testset "Property 3: RIGHT_SUBSET (T(X) ⊃ T(Y))" begin
            px = FastITNode(Int32[1], FastBitTidset(BitVector([1, 1, 1, 1])))
            py = FastITNode(Int32[2], FastBitTidset(BitVector([1, 1, 0, 0])))

            res = charm_property_bit(px, py, minsup)
            @test res.frequent == true
            @test res.relation == RIGHT_SUBSET
            @test res.candidate.items == Int32[1, 2]
            @test res.candidate.tids === py.tids
        end

        @testset "Property 4: INCOMPARABLE (T(X) ≠ T(Y))" begin
            px = FastITNode(Int32[1], FastBitTidset(BitVector([1, 1, 1, 0])))
            py = FastITNode(Int32[2], FastBitTidset(BitVector([0, 1, 1, 1])))

            res = charm_property_bit(px, py, minsup)
            @test res.frequent == true
            @test res.relation == INCOMPARABLE
            @test res.candidate.items == Int32[1, 2]
            @test res.candidate.tids.bits == BitVector([0, 1, 1, 0])
            @test res.candidate.tids.supp == 2
        end

        @testset "Infrequent Pruning (Zero Heap Allocation)" begin
            px = FastITNode(Int32[1], FastBitTidset(BitVector([1, 1, 0])))
            py = FastITNode(Int32[2], FastBitTidset(BitVector([0, 1, 1])))

            res = charm_property_bit(px, py, minsup)
            @test res.frequent == false
            @test res.relation === nothing
            @test res.candidate === nothing
            @test_throws ArgumentError charm_property_bit(px, py, 0)
        end
    end

    @testset "4. Optimized Repository & 64-bit XOR Checksum" begin
        repo = FastRepository()

        # Trong bản gốc: t1 = [1, 2, 5] (sum=8) và t3 = [2, 6] (sum=8) bị đụng độ băm!
        # Trong bản tối ưu: 64-bit XOR checksum phân biệt hoàn toàn 2 bitvector này
        t1 = FastBitTidset(BitVector([1, 1, 0, 0, 1, 0]))
        t3 = FastBitTidset(BitVector([0, 1, 0, 0, 0, 1]))
        @test t1.checksum != t3.checksum

        tids_common = FastBitTidset(BitVector([1, 1, 1, 0]))
        node_y = FastITNode(Int32[1, 2], tids_common)
        @test consider_bit!(repo, node_y) == true

        node_sub = FastITNode(Int32[1], tids_common)
        @test consider_bit!(repo, node_sub) == false

        node_super = FastITNode(Int32[1, 2, 3], tids_common)
        @test consider_bit!(repo, node_super) == true

        res = results_bit(repo, ["1", "2", "3"])
        @test length(res) == 1
        @test res[1].items == ["1", "2", "3"]
        @test res[1].support == 3
    end

    @testset "5. Pasquier 1999 Exact Integration & Baseline Equivalence" begin
        toy_path = joinpath(@__DIR__, "..", "data", "toy", "contextPasquier99.txt")
        transactions = load_transactions(toy_path)
        db_basic = to_vertical(transactions)
        db_opt   = to_vertical_bit(transactions)

        # Kiểm tra khớp tuyệt đối với bản cơ bản ở mọi mức minsup từ 1 đến 9
        for minsup in 1:length(transactions)
            res_basic = charm(db_basic, minsup)
            res_opt   = charm_bit(db_opt, minsup)
            @test res_basic == res_opt
        end

        # Boundary & Edge Cases
        @test isempty(charm_bit(db_opt, 100))
        @test_throws ArgumentError charm_bit(db_opt, 0)
        empty_db = to_vertical_bit(Vector{Item}[])
        @test isempty(charm_bit(empty_db, 2))
    end
end