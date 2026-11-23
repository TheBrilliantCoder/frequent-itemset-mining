"""Create SVG scalability plots from scalability_summary.csv.

Run with:

    julia comparison/plot_scalability.jl

Set `SCALABILITY_SUMMARY` and `PLOT_OUTPUT` to override the input CSV and
output directory.  Three plots are written, one line per implementation:

  * scalability_runtime.svg : net runtime vs number of transactions (linear axes)
  * scalability_loglog.svg  : the same data on log-log axes; a straight line
                              means polynomial growth and its slope is the exponent
  * scalability_memory.svg  : peak memory vs number of transactions

Net runtime is the wall time minus the Julia/JVM start-up baseline.  The plots
are generated without external Julia packages.
"""

const INPUT_PATH = get(ENV, "SCALABILITY_SUMMARY", joinpath(@__DIR__, "metrics/scalability_summary.csv"))
const OUTPUT_DIR = get(ENV, "PLOT_OUTPUT", joinpath(@__DIR__, "plots"))

const IMPLEMENTATIONS = ["basic", "optimized", "spmf"]
const LABELS = Dict("basic" => "Basic", "optimized" => "Optimized", "spmf" => "SPMF")
const COLORS = Dict("basic" => "#1565c0", "optimized" => "#2e7d32", "spmf" => "#d84315")
const TIME_FLOOR = 1.0e-3   # keeps zero-second runs drawable on a log axis

xml_escape(value) = replace(string(value), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

function read_results(path)
    isfile(path) || error("Scalability CSV not found: $path (run compare_scalability.jl first)")
    lines = readlines(path)
    isempty(lines) && error("Scalability CSV is empty: $path")
    headers = split(strip(first(lines)), ',')
    columns = Dict(name => findfirst(==(name), headers) for name in
                   ["dataset", "implementation", "transactions", "net_seconds", "median_peak_mb"])
    any(isnothing, values(columns)) && error("CSV is missing required scalability columns")

    rows = NamedTuple[]
    for line in lines[2:end]
        isempty(strip(line)) && continue
        fields = split(line, ',')
        push!(rows, (
            dataset = fields[columns["dataset"]],
            impl = fields[columns["implementation"]],
            n = parse(Int, fields[columns["transactions"]]),
            seconds = parse(Float64, fields[columns["net_seconds"]]),
            peak = parse(Float64, fields[columns["median_peak_mb"]]),
        ))
    end
    return rows
end

function nice_maximum(value)
    value <= 0 && return 1.0
    magnitude = 10.0^floor(log10(value))
    for step in (1.0, 2.0, 5.0, 10.0)
        step * magnitude >= value && return step * magnitude
    end
    return 10.0 * magnitude
end

format_value(value) = value >= 100 ? string(round(Int, value)) :
                      value >= 1 ? string(round(value; digits = 1)) : string(round(value; digits = 3))

function write_line_plot(path, title, xlabel, ylabel, rows, field; log_axes = false)
    impls = [impl for impl in IMPLEMENTATIONS if any(row.impl == impl for row in rows)]
    series = Dict(impl => sort([row for row in rows if row.impl == impl], by = row -> row.n) for impl in impls)
    value(row) = log_axes && field == :seconds ? max(getfield(row, field), TIME_FLOOR) : getfield(row, field)

    xs = sort(unique(row.n for row in rows))
    ys = Float64[value(row) for row in rows]

    width, height = 900, 600
    left, right, top, bottom = 90, 30, 70, 80
    plot_width, plot_height = width - left - right, height - top - bottom

    if log_axes
        lx0, lx1 = log10(minimum(xs)) - 0.08, log10(maximum(xs)) + 0.08
        ly0, ly1 = floor(log10(minimum(ys))), ceil(log10(maximum(ys)))
        ly1 == ly0 && (ly1 += 1)

        xmap = v -> left + plot_width * (log10(v) - lx0) / (lx1 - lx0)
        ymap = v -> top + plot_height * (1 - (log10(v) - ly0) / (ly1 - ly0))

        yticks = [10.0^e for e in ly0:ly1]
        xticks = Float64.(xs)
    else
        xmax = Float64(maximum(xs))
        ymax = nice_maximum(maximum(ys))

        xmap = v -> left + plot_width * v / xmax
        ymap = v -> top + plot_height * (1 - v / ymax)

        yticks = [ymax * k / 5 for k in 0:5]
        xticks = Float64.(xs)
    end

    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
        println(io, "<text x=\"$(width ÷ 2)\" y=\"28\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"20\">$(xml_escape(title))</text>")
        for tick in yticks
            yy = ymap(tick)
            println(io, "<line x1=\"$left\" y1=\"$yy\" x2=\"$(left + plot_width)\" y2=\"$yy\" stroke=\"#dddddd\"/>")
            println(io, "<text x=\"$(left - 8)\" y=\"$(yy + 4)\" text-anchor=\"end\" font-family=\"sans-serif\" font-size=\"12\">$(format_value(tick))</text>")
        end
        for tick in xticks
            xx = xmap(tick)
            println(io, "<line x1=\"$xx\" y1=\"$top\" x2=\"$xx\" y2=\"$(top + plot_height)\" stroke=\"#eeeeee\"/>")
            println(io, "<text x=\"$xx\" y=\"$(top + plot_height + 22)\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"12\">$(Int(tick))</text>")
        end
        println(io, "<line x1=\"$left\" y1=\"$top\" x2=\"$left\" y2=\"$(top + plot_height)\" stroke=\"black\"/>")
        println(io, "<line x1=\"$left\" y1=\"$(top + plot_height)\" x2=\"$(left + plot_width)\" y2=\"$(top + plot_height)\" stroke=\"black\"/>")

        for impl in impls
            points = join(("$(xmap(row.n)),$(ymap(value(row)))" for row in series[impl]), " ")
            println(io, "<polyline points=\"$points\" fill=\"none\" stroke=\"$(COLORS[impl])\" stroke-width=\"3\"/>")
            for row in series[impl]
                println(io, "<circle cx=\"$(xmap(row.n))\" cy=\"$(ymap(value(row)))\" r=\"5\" fill=\"white\" stroke=\"$(COLORS[impl])\" stroke-width=\"2\"/>")
            end
        end

        println(io, "<text x=\"$(width ÷ 2)\" y=\"$(height - 18)\" text-anchor=\"middle\" font-family=\"sans-serif\">$(xml_escape(xlabel))</text>")
        println(io, "<text transform=\"translate(18 $(height ÷ 2)) rotate(-90)\" text-anchor=\"middle\" font-family=\"sans-serif\">$(xml_escape(ylabel))</text>")

        legend_x = width - right
        for impl in reverse(impls)
            label = LABELS[impl]
            legend_x -= 40 + 9 * length(label)
            println(io, "<line x1=\"$legend_x\" y1=\"35\" x2=\"$(legend_x + 25)\" y2=\"35\" stroke=\"$(COLORS[impl])\" stroke-width=\"3\"/><text x=\"$(legend_x + 32)\" y=\"39\" font-family=\"sans-serif\">$label</text>")
        end
        println(io, "</svg>")
    end
end

function main()
    mkpath(OUTPUT_DIR)
    rows = read_results(INPUT_PATH)
    isempty(rows) && error("No scalability rows found in $INPUT_PATH")
    dataset = first(rows).dataset

    runtime = joinpath(OUTPUT_DIR, "scalability_runtime.svg")
    write_line_plot(runtime, "Runtime vs database size: $dataset",
                    "Number of transactions", "Net runtime (seconds)", rows, :seconds)
    println("Wrote $runtime")

    loglog = joinpath(OUTPUT_DIR, "scalability_loglog.svg")
    write_line_plot(loglog, "Runtime vs database size (log-log): $dataset",
                    "Number of transactions (log scale)", "Net runtime (seconds, log scale)",
                    rows, :seconds; log_axes = true)
    println("Wrote $loglog")

    memory = joinpath(OUTPUT_DIR, "scalability_memory.svg")
    write_line_plot(memory, "Peak memory vs database size: $dataset",
                    "Number of transactions", "Peak memory (MB)", rows, :peak)
    println("Wrote $memory")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
