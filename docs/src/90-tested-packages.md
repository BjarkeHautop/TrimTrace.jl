# Tested packages

TrimTrace run on two of my own packages. Both already compile under `--trim=safe` and
have a hand-written trim check, so each report can be compared against a known answer.

Run on 2026-11-11 with Julia 1.13.3 and JuliaC 0.3.12.

## How the runs were made

For each package, I instantiated its test environment and ran:

```julia
using TrimTrace, Sugiyama

result = record_and_check(Sugiyama)
display(result)
uncovered(Sugiyama, result.signatures)
```

## Results

| Package | Commit | Signatures | Uncovered | Errors (value-dependent) |
|---|---|---|---|---|
| [Sugiyama.jl](https://github.com/BjarkeHautop/Sugiyama.jl) | [`4eac6d9`](https://github.com/BjarkeHautop/Sugiyama.jl/commit/4eac6d9afa986b742c93ebf935093bd47cb10fc9) (v1.0.1) | 18 | 0 | 1 (1) |
| [CausalStructures.jl](https://github.com/BjarkeHautop/CausalStructures.jl) | [`ad547b9`](https://github.com/BjarkeHautop/CausalStructures.jl/commit/ad547b95eb87598406d23a2bebe46fb6b576a325) (1.2.1-DEV) | 715 | 4 | 6 (6) |

Every error is a value-dependent false alarm, and both packages pass with their
`test/trim-allow.txt`.

**Uncovered** counts the public functions and types that no recorded call reaches
directly, so they are never checked. Their code may still run during the tests, inside
other calls.

**Value-dependent** reports come from a type or symbol passed as an argument; see
[Only argument types are recorded](@ref). To decide whether each was a real problem, I
compiled the same call with the literal value under `--trim=safe`.

## Sugiyama.jl

All public names are covered, and 17 of the 18 signatures pass. They include calls
through a layout object, such as
`(::Sugiyama.SugiyamaLayout{Float64, Float64})(::Array{Int64, 2})`, a
`Graphs.SimpleDiGraph` input through the Graphs extension, and sparse-matrix inputs that
the package's hand-written check doesn't cover.

The error is `SugiyamaLayout(; Ptype::DataType)`. `Ptype` sets the output point type, and
as a runtime `DataType` the layout's type can't be inferred. With a literal, as in
`SugiyamaLayout(; Ptype = Float32)`, it compiles; the package's
[TrimCheck workflow](https://github.com/BjarkeHautop/Sugiyama.jl/blob/main/.github/workflows/TrimCheck.yml)
checks exactly that call. Its allowlist:

```text
# `Ptype` is a literal type in real calls; only the recorded DataType fails to infer.
r"^Sugiyama\.(sugiyama|sugiyama_paths|SugiyamaLayout)\(.*Ptype::DataType"
```

## CausalStructures.jl

Four public names are uncovered. The tests never use `RequiredEdge` or
`uniform_dag_counts`, only print a `ForbiddenEdge` built elsewhere, and use `Estimand`
only as a type, as in `one(Estimand)` and `Estimand[]`.

All six errors come from the `class` keyword of `generate_graph`, which picks the kind of
graph to return; as a runtime `DataType`, the return type can't be inferred. With a
literal, as in `generate_graph(10; p = 0.3, class = ADMG, latents = 2)`, it compiles, with
or without an explicit RNG; the package's
[TrimCheck workflow](https://github.com/BjarkeHautop/CausalStructures.jl/blob/main/.github/workflows/TrimCheck.yml)
checks both forms. Its allowlist:

```text
# `class` is a literal type in real calls; only the recorded DataType fails to infer.
r"^CausalStructures\.generate_graph\(.*class::DataType"
```
