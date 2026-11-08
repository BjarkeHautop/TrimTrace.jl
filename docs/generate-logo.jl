# Writes the logo (light and dark variants) and the shields.io badge description into
# docs/src/assets. Run with `julia docs/generate-logo.jl`; no packages needed.

const jl_purple = "#9558B2"
const jl_red = "#CB3C33"
const jl_green = "#389826"

# Three call sites joined by a dashed trace, laid out as a check mark.
const points = [(80, 235), (195, 355), (400, 105)]
const colors = [jl_red, jl_green, jl_purple]

function logo_svg(ink; width = 480, height = 460, radius = 44, stroke = 16, dash = "20 18")
    trace = join(("$x,$y" for (x, y) in points), " ")
    dots = join(
        (
            """<circle cx="$x" cy="$y" r="$radius" fill="$c"/>""" for
            ((x, y), c) in zip(points, colors)
        ),
        "\n  ",
    )
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 480 460">
      <polyline points="$trace" fill="none" stroke="$ink" stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="$dash"/>
      $dots
    </svg>
    """
end

const dir = joinpath(@__DIR__, "src", "assets")
mkpath(dir)

for (file, ink) in [("logo.svg", "#1C1A20"), ("logo-dark.svg", "#E4E1E8")]
    write(joinpath(dir, file), logo_svg(ink))
    println("saved ", joinpath(dir, file))
end

# Badge for packages that run TrimTrace in CI, rendered by shields.io's endpoint badge:
# https://img.shields.io/endpoint?url=<raw URL of badge.json>
badge_logo =
    replace(logo_svg("#E4E1E8"; width = 48, height = 46), "\n" => "", "\"" => "\\\"")
write(
    joinpath(dir, "badge.json"),
    """
    {
      "schemaVersion": 1,
      "label": "TrimTrace",
      "message": "trim=safe",
      "color": "$jl_purple",
      "logoSvg": "$(replace(badge_logo, r">\s+<" => "><"))"
    }
    """,
)
println("saved ", joinpath(dir, "badge.json"))
