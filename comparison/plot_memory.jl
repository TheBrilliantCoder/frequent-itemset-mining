"""Create SVG memory comparison plots from memory_summary.csv.

Run with:

    julia comparison/plot_memory.jl

Set `MEMORY_SUMMARY` and `PLOT_OUTPUT` to override the input CSV and output
directory.  Two grouped bar charts are written (one group per dataset, one bar
per implementation):

  * memory_peak.svg : median peak RSS in MB (what the OS really used)
  * memory_net.svg  : peak minus the Julia/JVM start-up baseline in MB

The implementations that are present in the CSV are plotted, so the
`optimized` bars appear automatically once that implementation was benchmarked.
The plots are generated without external Julia packages.
"""

const INPUT_PATH = get(ENV, "MEMORY_SUMMARY", joinpath(@__DIR__, "metrics/memory_summary.csv"))
const OUTPUT_DIR = get(ENV, "PLOT_OUTPUT", joinpath(@__DIR__, "plots"))

# Drawing order, labels and colors of the implementations.
const IMPLEMENTATIONS = ["basic", "optimized", "spmf"]
const LABELS = Dict("basic" => "Basic", "optimized" => "Optimized", "spmf" => "SPMF")
const COLORS = Dict("basic" => "#1565c0", "optimized" => "#2e7d32", "spmf" => "#d84315")

function xml_escape(value)
    replace(string(value), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")
end

function read_results(path)
    isfile(path) || error("Memory summary CSV not found: $path (run compare_memory.jl first)")
    lines = readlines(path)
    isempty(lines) && error("Memory summary CSV is empty: $path")
    headers = split(strip(first(lines)), ',')
    columns = Dict(name => findfirst(==(name), headers) for name in
                   ["dataset", "minsup_ratio", "implementation",
                    "median_peak_mb", "median_net_mb"])
    any(isnothing, values(columns)) && error("CSV is missing required memory columns")

    rows = NamedTuple[]
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(line, ',')
        push!(rows, (
            dataset = fields[columns["dataset"]],
            ratio = parse(Float64, fields[columns["minsup_ratio"]]),
            impl = fields[columns["implementation"]],
            peak = parse(Float64, fields[columns["median_peak_mb"]]),
            net = parse(Float64, fields[columns["median_net_mb"]]),
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

function format_value(value)
    value >= 100 ? string(round(Int, value)) : string(round(value; digits = 1))
end

function write_bar_plot(path, title, ylabel, rows, field)
    datasets = unique(row.dataset for row in rows)
    impls = [impl for impl in IMPLEMENTATIONS if any(row.impl == impl for row in rows)]
    lookup = Dict((row.dataset, row.impl) => row for row in rows)
    ratio_of = Dict(row.dataset => row.ratio for row in rows)

    width, height = 1000, 600
    left, right, top, bottom = 90, 30, 70, 90
    plot_width, plot_height = width - left - right, height - top - bottom

    all_values = Float64[getfield(row, field) for row in rows]
    maximum_value = nice_maximum(maximum(all_values))
    y(value) = top + plot_height * (1 - value / maximum_value)

    group_width = plot_width / length(datasets)
    bar_width = min(group_width * 0.8 / length(impls), 60.0)
    cluster_width = bar_width * length(impls)

    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$(width ÷ 2)\" y=\"28\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"20\">$(xml_escape(title))</text>")

        # Grid and y axis
        for tick in 0:5
            value = maximum_value * tick / 5
            yy = y(value)
            println(io, "<line x1=\"$left\" y1=\"$yy\" x2=\"$(left + plot_width)\" y2=\"$yy\" stroke=\"#dddddd\"/>")
            println(io, "<text x=\"$(left - 8)\" y=\"$(yy + 4)\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">$(format_value(value))</text>")
        end
        println(io, "<line x1=\"$left\" y1=\"$top\" x2=\"$left\" y2=\"$(top + plot_height)\" stroke=\"black\"/>")
        println(io, "<line x1=\"$left\" y1=\"$(top + plot_height)\" x2=\"$(left + plot_width)\" y2=\"$(top + plot_height)\" stroke=\"black\"/>")

        # Bars, value labels and dataset labels
        for (g, dataset) in enumerate(datasets)
            center = left + (g - 0.5) * group_width
            start = center - cluster_width / 2
            for (k, impl) in enumerate(impls)
                haskey(lookup, (dataset, impl)) || continue
                value = getfield(lookup[(dataset, impl)], field)
                bx = start + (k - 1) * bar_width
                by = y(value)
                bar_height = max(top + plot_height - by, 0.0)
                println(io, "<rect x=\"$(bx + 2)\" y=\"$by\" width=\"$(bar_width - 4)\" height=\"$bar_height\" fill=\"$(COLORS[impl])\"/>")
                println(io, "<text x=\"$(bx + bar_width / 2)\" y=\"$(by - 6)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"11\">$(format_value(value))</text>")
            end
            println(io, "<text x=\"$center\" y=\"$(top + plot_height + 22)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"13\">$(xml_escape(dataset))</text>")
            println(io, "<text x=\"$center\" y=\"$(top + plot_height + 39)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"11\" fill=\"#555555\">minsup $(round(ratio_of[dataset] * 100; digits=1))%</text>")
        end

        println(io, "<text x=\"$(width ÷ 2)\" y=\"$(height - 18)\" text-anchor=\"middle\" font-family=\"sans-serif\">Dataset</text>")
        println(io, "<text transform=\"translate(18 $(height ÷ 2)) rotate(-90)\" text-anchor=\"middle\" font-family=\"sans-serif\">$(xml_escape(ylabel))</text>")

        # Legend (right-aligned, laid out from the right edge)
        legend_x = width - right
        for impl in reverse(impls)
            label = LABELS[impl]
            legend_x -= 30 + 9 * length(label)
            println(io, "<rect x=\"$legend_x\" y=\"28\" width=\"14\" height=\"14\" fill=\"$(COLORS[impl])\"/>")
            println(io, "<text x=\"$(legend_x + 20)\" y=\"40\" font-family=\"sans-serif\" font-size=\"13\">$label</text>")
        end
        println(io, "</svg>")
    end
end

function main()
    mkpath(OUTPUT_DIR)
    rows = read_results(INPUT_PATH)
    isempty(rows) && error("No memory rows found in $INPUT_PATH")

    peak_output = joinpath(OUTPUT_DIR, "memory_peak.svg")
    write_bar_plot(peak_output, "Peak memory (RSS) at median minsup",
                   "Peak memory (MB)", rows, :peak)
    println("Wrote $peak_output")

    net_output = joinpath(OUTPUT_DIR, "memory_net.svg")
    write_bar_plot(net_output, "Net memory (peak minus start-up baseline) at median minsup",
                   "Net memory (MB)", rows, :net)
    println("Wrote $net_output")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
