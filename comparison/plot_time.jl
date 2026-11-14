"""Create one SVG runtime comparison plot per dataset from time_result.csv.

Run with:

    julia comparison/plot_time.jl

Set `TIME_RESULTS` and `PLOT_OUTPUT` to override the input CSV and output
directory.  The plot is generated without external Julia packages.
"""

const INPUT_PATH = get(ENV, "TIME_RESULTS", joinpath(@__DIR__, "time_result.csv"))
const OUTPUT_DIR = get(ENV, "PLOT_OUTPUT", joinpath(@__DIR__, "plots"))

function xml_escape(value)
    replace(string(value), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")
end

function read_results(path)
    isfile(path) || error("Timing CSV not found: $path")
    lines = readlines(path)
    isempty(lines) && error("Timing CSV is empty: $path")
    headers = split(strip(first(lines)), ',')
    columns = Dict(name => findfirst(==(name), headers) for name in
                   ["dataset", "minsup_ratio", "julia_seconds", "spmf_seconds",
                    "julia_itemsets", "spmf_itemsets"])
    any(isnothing, values(columns)) && error("CSV is missing required timing columns")

    rows = NamedTuple[]
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(line, ',')
        push!(rows, (
            dataset = fields[columns["dataset"]],
            ratio = parse(Float64, fields[columns["minsup_ratio"]]),
            julia = parse(Float64, fields[columns["julia_seconds"]]),
            spmf = parse(Float64, fields[columns["spmf_seconds"]]),
            julia_itemsets = parse(Int, fields[columns["julia_itemsets"]]),
            spmf_itemsets = parse(Int, fields[columns["spmf_itemsets"]]),
        ))
    end
    return rows
end

function write_itemset_plot(path, dataset, rows)
    width, height = 900, 600
    left, right, top, bottom = 90, 30, 55, 80
    plot_width, plot_height = width - left - right, height - top - bottom
    ratios = [row.ratio for row in rows]
    julia = Float64[row.julia_itemsets for row in rows]
    spmf = Float64[row.spmf_itemsets for row in rows]
    maximum_count = max(maximum(julia), maximum(spmf), 1.0)
    x = [left + (i - 1) * plot_width / max(length(rows) - 1, 1) for i in eachindex(rows)]
    y(value) = top + plot_height * (1 - value / maximum_count)

    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$(width ÷ 2)\" y=\"28\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"20\">Frequent itemsets: $(xml_escape(dataset))</text>")
        println(io, "<line x1=\"$left\" y1=\"$top\" x2=\"$left\" y2=\"$(top + plot_height)\" stroke=\"black\"/>")
        println(io, "<line x1=\"$left\" y1=\"$(top + plot_height)\" x2=\"$(left + plot_width)\" y2=\"$(top + plot_height)\" stroke=\"black\"/>")
        for tick in 0:5
            value = maximum_count * tick / 5
            yy = y(value)
            println(io, "<line x1=\"$left\" y1=\"$yy\" x2=\"$(left + plot_width)\" y2=\"$yy\" stroke=\"#dddddd\"/>")
            println(io, "<text x=\"$(left - 8)\" y=\"$(yy + 4)\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">$(round(value; digits=0))</text>")
        end
        for (xx, ratio) in zip(x, ratios)
            println(io, "<text x=\"$xx\" y=\"$(top + plot_height + 22)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(round(ratio * 100; digits=1))%</text>")
        end
        println(io, "<polyline points=\"$(line_points(julia, x, y))\" fill=\"none\" stroke=\"#1565c0\" stroke-width=\"3\"/>")
        println(io, "<polyline points=\"$(line_points(spmf, x, y))\" fill=\"none\" stroke=\"#d84315\" stroke-width=\"3\"/>")
        write_markers(io, julia, spmf, x, y)
        println(io, "<text x=\"$(width ÷ 2)\" y=\"$(height - 18)\" text-anchor=\"middle\" font-family=\"sans-serif\">Minimum support (high to low)</text>")
        println(io, "<text transform=\"translate(18 $(height ÷ 2)) rotate(-90)\" text-anchor=\"middle\" font-family=\"sans-serif\">Number of frequent itemsets</text>")
        println(io, "<line x1=\"$(width - 220)\" y1=\"35\" x2=\"$(width - 195)\" y2=\"35\" stroke=\"#1565c0\" stroke-width=\"3\"/><text x=\"$(width - 188)\" y=\"39\" font-family=\"sans-serif\">Group</text>")
        println(io, "<line x1=\"$(width - 120)\" y1=\"35\" x2=\"$(width - 95)\" y2=\"35\" stroke=\"#d84315\" stroke-width=\"3\"/><text x=\"$(width - 88)\" y=\"39\" font-family=\"sans-serif\">SPMF</text>")
        println(io, "</svg>")
    end
end

function line_points(values, x_positions, y)
    join(("$(x_positions[i]),$(y(values[i]))" for i in eachindex(values)), " ")
end

function write_markers(io, julia, spmf, x_positions, y)
    for i in eachindex(x_positions)
        println(io, "<circle cx=\"$(x_positions[i])\" cy=\"$(y(julia[i]))\" r=\"5\" fill=\"white\" stroke=\"#1565c0\" stroke-width=\"2\"/>")
        println(io, "<rect x=\"$(x_positions[i] - 5)\" y=\"$(y(spmf[i]) - 5)\" width=\"10\" height=\"10\" fill=\"white\" stroke=\"#d84315\" stroke-width=\"2\"/>")
    end
end

function write_plot(path, dataset, rows)
    width, height = 900, 600
    left, right, top, bottom = 90, 30, 55, 80
    plot_width, plot_height = width - left - right, height - top - bottom
    ratios = [row.ratio for row in rows]
    julia = [row.julia for row in rows]
    spmf = [row.spmf for row in rows]
    maximum_time = max(maximum(julia), maximum(spmf), eps())
    x = [left + (i - 1) * plot_width / max(length(rows) - 1, 1) for i in eachindex(rows)]
    y(value) = top + plot_height * (1 - value / maximum_time)

    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$(width ÷ 2)\" y=\"28\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"20\">Runtime: $(xml_escape(dataset))</text>")
        println(io, "<line x1=\"$left\" y1=\"$top\" x2=\"$left\" y2=\"$(top + plot_height)\" stroke=\"black\"/>")
        println(io, "<line x1=\"$left\" y1=\"$(top + plot_height)\" x2=\"$(left + plot_width)\" y2=\"$(top + plot_height)\" stroke=\"black\"/>")
        for tick in 0:5
            value = maximum_time * tick / 5
            yy = y(value)
            println(io, "<line x1=\"$left\" y1=\"$yy\" x2=\"$(left + plot_width)\" y2=\"$yy\" stroke=\"#dddddd\"/>")
            println(io, "<text x=\"$(left - 8)\" y=\"$(yy + 4)\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">$(round(value; digits=2))</text>")
        end
        for (xx, ratio) in zip(x, ratios)
            println(io, "<text x=\"$xx\" y=\"$(top + plot_height + 22)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(round(ratio * 100; digits=1))%</text>")
        end
        println(io, "<polyline points=\"$(line_points(julia, x, y))\" fill=\"none\" stroke=\"#1565c0\" stroke-width=\"3\"/>")
        println(io, "<polyline points=\"$(line_points(spmf, x, y))\" fill=\"none\" stroke=\"#d84315\" stroke-width=\"3\"/>")
        write_markers(io, julia, spmf, x, y)
        println(io, "<text x=\"$(width ÷ 2)\" y=\"$(height - 18)\" text-anchor=\"middle\" font-family=\"sans-serif\">Minimum support (high to low)</text>")
        println(io, "<text transform=\"translate(18 $(height ÷ 2)) rotate(-90)\" text-anchor=\"middle\" font-family=\"sans-serif\">Runtime (seconds)</text>")
        println(io, "<line x1=\"$(width - 220)\" y1=\"35\" x2=\"$(width - 195)\" y2=\"35\" stroke=\"#1565c0\" stroke-width=\"3\"/><text x=\"$(width - 188)\" y=\"39\" font-family=\"sans-serif\">Group</text>")
        println(io, "<line x1=\"$(width - 120)\" y1=\"35\" x2=\"$(width - 95)\" y2=\"35\" stroke=\"#d84315\" stroke-width=\"3\"/><text x=\"$(width - 88)\" y=\"39\" font-family=\"sans-serif\">SPMF</text>")
        println(io, "</svg>")
    end
end

function main()
    mkpath(OUTPUT_DIR)
    rows = read_results(INPUT_PATH)
    datasets = unique(row.dataset for row in rows)
    isempty(datasets) && error("No timing rows found in $INPUT_PATH")
    for dataset in datasets
        dataset_rows = sort(filter(row -> row.dataset == dataset, rows), by = row -> -row.ratio)
        output = joinpath(OUTPUT_DIR, dataset * "_runtime.svg")
        write_plot(output, dataset, dataset_rows)
        println("Wrote $output")
        itemset_output = joinpath(OUTPUT_DIR, dataset * "_itemsets.svg")
        write_itemset_plot(itemset_output, dataset, dataset_rows)
        println("Wrote $itemset_output")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
