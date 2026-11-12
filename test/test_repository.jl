using Test
using CharmMining

@testset "Hash Subsumption Repository Tests" begin
    repo = ClosedItemsetRepository()

    @testset "TID Checksum Verification" begin
        t1 = BitSet([1, 2, 5])
        t2 = BitSet([1, 2, 5])
        t3 = BitSet([2, 6]) 

        @test CharmMining.tid_checksum(t1) == UInt64(8)
        @test CharmMining.tid_checksum(t1) == CharmMining.tid_checksum(t2)
        @test CharmMining.tid_checksum(t1) == CharmMining.tid_checksum(t3)
    end

    @testset "Fast Subsumption Checking with consider!" begin
        # 1. Thêm tập đóng Y = {"1", "2"}, sup = 3, tids = [1, 2, 3]
        node_y = ITPair(Itemset(["1", "2"]), BitSet([1, 2, 3]))
        @test consider!(repo, node_y) == true

        # 2. Candidate X = {"1"} là tập con của {"1", "2"} và có cùng support (3)
        # -> Bị subsumed, consider! phải trả về false
        node_sub = ITPair(Itemset(["1"]), BitSet([1, 2, 3]))
        @test consider!(repo, node_sub) == false

        # 3. Candidate X = {"3"} có cùng support (3) nhưng tids khác -> Được nhận
        node_diff = ITPair(Itemset(["3"]), BitSet([1, 2, 4]))
        @test consider!(repo, node_diff) == true

        # 4. Candidate X = {"1", "2", "3"} là superset đến sau có cùng tids
        # -> consider! chấp nhận và loại bỏ tập con cũ
        node_super = ITPair(Itemset(["1", "2", "3"]), BitSet([1, 2, 3]))
        @test consider!(repo, node_super) == true
    end

    @testset "Results Formatting and Sorting" begin
        res = results(repo)
        @test res isa Vector{ClosedItemset}
        # Kết quả phải sắp xếp theo support giảm dần
        @test issorted([r.support for r in res], rev = true)
        # Từng tập itemset phải được sắp xếp từ điển
        for r in res
            @test issorted(r.items)
        end
    end
end