using Test
using CharmMining

@testset "Data Loading and Preprocessing Tests" begin
    @testset "Load transactions and filter comments" begin
        # Tạo file tạm chứa comment, dòng trống và item lộn xộn
        tmp_input = tempname() * ".txt"
        open(tmp_input, "w") do io
            println(io, "# Comment bắt đầu bằng #")
            println(io, "% Comment bắt đầu bằng %")
            println(io, "@ Comment bắt đầu bằng @")
            println(io, "")
            println(io, "1 2 5")
            println(io, "2 4")
            println(io, "2 1 2") 
            println(io, "2 3")
        end

        transactions = load_transactions(tmp_input)
        rm(tmp_input, force = true)

        @test length(transactions) == 4
        @test transactions[1] == ["1", "2", "5"]
        @test transactions[2] == ["2", "4"]
        @test transactions[3] == ["1", "2"]
        @test transactions[4] == ["2", "3"]
    end

    @testset "Horizontal to Vertical Database Conversion" begin
        transactions = [
            ["1", "2", "5"],
            ["2", "4"],
            ["2", "3"],
            ["1", "2", "4"]
        ]
        vdb = to_vertical(transactions)

        @test vdb isa VerticalDB
        @test vdb["1"] == BitSet([1, 4])
        @test vdb["2"] == BitSet([1, 2, 3, 4])
        @test vdb["5"] == BitSet([1])
        @test !haskey(vdb, "99")
    end

    @testset "Frequent Singletons Filtering" begin
        transactions = [
            ["1", "2", "5"],
            ["2", "4"],
            ["2", "3"],
            ["1", "2", "4"]
        ]
        vdb = to_vertical(transactions)
        
        singletons = frequent_singletons(vdb, 2)
        items_found = [first(node.items) for node in singletons]

        @test !("5" in items_found)
        @test "1" in items_found
        @test "2" in items_found
        @test "4" in items_found
    end

    @testset "Export Results SPMF format" begin
        tmp_output = tempname() * ".txt"
        closed_itemsets = [
            ClosedItemset(["1", "2"], 4),
            ClosedItemset(["2"], 7)
        ]
        export_result(tmp_output; fmt = :txt, itemsets = closed_itemsets)

        lines = readlines(tmp_output)
        rm(tmp_output, force = true)

        @test length(lines) == 2
        @test lines[1] == "1 2 #SUP: 4"
        @test lines[2] == "2 #SUP: 7"
        @test_throws ArgumentError export_result(tmp_output; fmt = :csv, itemsets = closed_itemsets)
    end
end