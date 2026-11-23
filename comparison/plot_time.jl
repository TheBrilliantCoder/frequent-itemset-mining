"""Create SVG runtime plots from time_result.csv (basic vs optimized vs SPMF).

Run with:

    julia comparison/plot_time.jl

Set `TIME_RESULTS` and `PLOT_OUTPUT` to override the input CSV and output
directory.  For every dataset two plots are written:

  * <dataset>_runtime.svg  : net runtime (wall time minus Julia/JVM start-up)
                             of the three implementations vs minimum support
  * <dataset>_itemsets.svg : number of closed itemsets found vs minimum support

Rows whose `status` is not `ok` (memory limit hit, run failed) are left out.
The plots are generated without external Julia packages.
"""

const INPUT_PATH = get(ENV, "TIME_RESULTS", joinpath(@__DIR__, "metrics/time_result.csv"))
const OUTPUT_DIR = get(ENV, "PLOT_OUTPUT", joinpath(@__DIR__, "plots"))

const IMPLEMENTATIONS = ["basic", "optimized", "spmf"]
const LABELS = Dict("basic" => "Basic", "optimized" => "Optimized", "spmf" => "SPMF")
const COLORS = Dict("basic" => "#1565c0", "optimized" => "#2e7d32", "spmf" => "#d84315")

xml_escape(value) = replace(string(value), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

function read_results(path)
    isfile(path) || error("Timing CSV not found: $path (run compare_time.jl first)")
    lines = readlines(path)
    isempty(lines) && error("Timing CSV is empty: $path")
    headers = split(strip(first(lines)), ',')
    required = ["dataset", "minsup_ratio", "implementation", "net_seconds", "itemsets", "status"]
    columns = Dict(name => findfirst(==(name), headers) for name in required)
    any(isnothing, values(columns)) && error("CSV is missing required columns: $(join(required, ", "))")

    rows = NamedTuple[]
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(line, ',')
        fields[columns["status"]] == "ok" || continue
        push!(rows, (
            dataset = fields[columns["dataset"]],
            ratio = parse(Float64, fields[columns["minsup_ratio"]]),
            impl = fields[columns["implementation"]],
            seconds = parse(Float64, fields[columns["net_seconds"]]),
            itemsets = parse(Int, fields[columns["itemsets"]]),
        ))
    end
    return rows
end

# Round the axis maximum up to 1, 2 or 5 times a power of ten.
function nice_maximum(value)
    value <= 0 && return 1.0
    magnitude = 10.0^floor(log10(value))
    for step in (1.0, 2.0, 5.0, 10.0)
        step * magnitude >= value && return step * magnitude
    end
    return 10.0 * magnitude
end

format_tick(value) = value >= 100 ? string(round(Int, value)) : string(round(value; digits = 2))

# Marker shape per implementation: circle, triangle, square.
function marker(impl, cx, cy, color)
    if impl == "basic"
        return "<circle cx=\"$cx\" cy=\"$cy\" r=\"5\" fill=\"white\" stroke=\"$color\" stroke-width=\"2\"/>"
    elseif impl == "optimized"
        return "<polygon points=\"$cx,$(cy - 6) $(cx - 6),$(cy + 5) $(cx + 6),$(cy + 5)\" fill=\"white\" stroke=\"$color\" stroke-width=\"2\"/>"
    end
    return "<rect x=\"$(cx - 5)\" y=\"$(cy - 5)\" width=\"10\" height=\"10\" fill=\"white\" stroke=\"$color\" stroke-width=\"2\"/>"
end

"""
Line chart. `series` is a Vector of (impl, values) where `values[i]` is the
value at ratios[i], or `nothing` when the point is missing.
"""
function write_line_plot(path, title, ylabel, ratios, series; legend = true)
    width, height = 900, 600
    left, right, top, bottom = 90, 30, 70, 80
    plot_width, plot_height = width - left - right, height - top - bottom
    all_values = Float64[v for (_, values) in series for v in values if v !== nothing]
    maximum_value = nice_maximum(isempty(all_values) ? 1.0 : maximum(all_values))
    x = [left + (i - 1) * plot_width / max(length(ratios) - 1, 1) for i in eachindex(ratios)]
    y(value) = top + plot_height * (1 - value / maximum_value)

    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$(width ÷ 2)\" y=\"28\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"20\">$(xml_escape(title))</text>")
        for tick in 0:5
            value = maximum_value * tick / 5
            yy = y(value)
            println(io, "<line x1=\"$left\" y1=\"$yy\" x2=\"$(left + plot_width)\" y2=\"$yy\" stroke=\"#dddddd\"/>")
            println(io, "<text x=\"$(left - 8)\" y=\"$(yy + 4)\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">$(format_tick(value))</text>")
        end
        println(io, "<line x1=\"$left\" y1=\"$top\" x2=\"$left\" y2=\"$(top + plot_height)\" stroke=\"black\"/>")
        println(io, "<line x1=\"$left\" y1=\"$(top + plot_height)\" x2=\"$(left + plot_width)\" y2=\"$(top + plot_height)\" stroke=\"black\"/>")
        for (xx, ratio) in zip(x, ratios)
            println(io, "<text x=\"$xx\" y=\"$(top + plot_height + 22)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(round(ratio * 100; digits = 1))%</text>")
        end

        for (impl, values) in series
            color = COLORS[impl]
            points = [(x[i], y(values[i])) for i in eachindex(values) if values[i] !== nothing]
            isempty(points) && continue
            println(io, "<polyline points=\"$(join(("$px,$py" for (px, py) in points), " "))\" fill=\"none\" stroke=\"$color\" stroke-width=\"3\"/>")
            for (px, py) in points
                println(io, marker(impl, px, py, color))
            end
        end

        println(io, "<text x=\"$(width ÷ 2)\" y=\"$(height - 18)\" text-anchor=\"middle\" font-family=\"sans-serif\">Minimum support (high to low)</text>")
        println(io, "<text transform=\"translate(18 $(height ÷ 2)) rotate(-90)\" text-anchor=\"middle\" font-family=\"sans-serif\">$(xml_escape(ylabel))</text>")

        # Legend, right-aligned on the title row below the title
        legend_x = width - right
        for (impl, _) in (legend ? reverse(series) : [])
            label = LABELS[impl]
            legend_x -= 45 + 9 * length(label)
            println(io, "<line x1=\"$legend_x\" y1=\"50\" x2=\"$(legend_x + 25)\" y2=\"50\" stroke=\"$(COLORS[impl])\" stroke-width=\"3\"/>")
            println(io, "<text x=\"$(legend_x + 32)\" y=\"54\" font-family=\"sans-serif\" font-size=\"13\">$label</text>")
        end
        println(io, "</svg>")
    end
end

function main()
    mkpath(OUTPUT_DIR)
    rows = read_results(INPUT_PATH)
    datasets = unique(row.dataset for row in rows)
    isempty(datasets) && error("No successful timing rows found in $INPUT_PATH")

    for dataset in datasets
        dataset_rows = filter(row -> row.dataset == dataset, rows)
        ratios = sort(unique(row.ratio for row in dataset_rows); rev = true)
        lookup = Dict((row.impl, row.ratio) => row for row in dataset_rows)
        impls = [impl for impl in IMPLEMENTATIONS if any(row.impl == impl for row in dataset_rows)]

        runtime_series = [(impl, Union{Float64,Nothing}[haskey(lookup, (impl, r)) ? lookup[(impl, r)].seconds : nothing for r in ratios]) for impl in impls]
        output = joinpath(OUTPUT_DIR, dataset * "_runtime.svg")
        write_line_plot(output, "Runtime: $dataset", "Net runtime (seconds, start-up excluded)", ratios, runtime_series)
        println("Wrote $output")

        # All implementations must find the same closed itemsets, so one line is enough.
        reference = first(impls)
        itemset_series = [(reference, Union{Float64,Nothing}[haskey(lookup, (reference, r)) ? Float64(lookup[(reference, r)].itemsets) : nothing for r in ratios])]
        itemset_output = joinpath(OUTPUT_DIR, dataset * "_itemsets.svg")
        write_line_plot(itemset_output, "Closed itemsets: $dataset", "Number of closed itemsets", ratios, itemset_series; legend = false)
        println("Wrote $itemset_output")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
