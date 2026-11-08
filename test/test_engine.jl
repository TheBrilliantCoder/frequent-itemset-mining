using Test
using CharmMining

@testset "CHARM Engine Integration Tests" begin
    toy_path = joinpath(@__DIR__, "..", "data", "toy", "contextPasquier99.txt")
    transactions = load_transactions(toy_path)
    db = to_vertical(transactions)

    # 9 tập đóng chuẩn lý thuyết tại minsup = 2
    expected_closed = Dict(
        ["2"] => 7,
        ["1"] => 6,
        ["3"] => 6,
        ["1", "2"] => 4,
        ["1", "3"] => 4,
        ["2", "3"] => 4,
        ["1", "2", "3"] => 2,
        ["1", "2", "5"] => 2,
        ["2", "4"] => 2
    )

    @testset "Pasquier 1999 Exact Correctness" begin
        res = charm(db, 2)
        @test length(res) == 9

        res_dict = Dict(r.items => r.support for r in res)
        for (expected_items, expected_sup) in expected_closed
            @test haskey(res_dict, expected_items)
            @test res_dict[expected_items] == expected_sup
        end

        # Kiểm tra tính Closed: tập ["5"] có sup = 2 nhưng không được xuất hiện độc lập
        # vì đã bị bao hàm bởi tập cha ["1", "2", "5"] cùng có sup = 2
        @test !haskey(res_dict, ["5"])
    end

    @testset "Boundary & Edge Cases" begin
        # minsup lớn hơn tổng số transaction -> rỗng
        @test isempty(charm(db, 100))

        # minsup < 1 -> báo lỗi
        @test_throws ArgumentError charm(db, 0)

        # CSDL rỗng
        empty_db = VerticalDB()
        @test isempty(charm(empty_db, 2))
    end
end