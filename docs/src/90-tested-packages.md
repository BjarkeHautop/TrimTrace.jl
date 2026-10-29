# Tested packages

Packages TrimTrace has been run against, what it found, and which reports are false alarms
that belong in the package's allowlist. Each run was `record`, then `uncovered`, then
`check` on the package's own test suite.

Setup: Julia 1.13.2, JuliaC 0.3.12, run on 2026-10-29.

| Package | Tested at | Signatures | Uncovered | Errors (value-dependent) | Verdict |
|---|---|---|---|---|---|
| [Sugiyama.jl](https://github.com/BjarkeHautop/Sugiyama.jl) | [`ff0c4f6`](https://github.com/BjarkeHautop/Sugiyama.jl/commit/ff0c4f60846dcc5cb39961ce5aae092106a1f7f8) (v1.0.1) | 17 | 0 | 1 (1) | Trim-compatible; 1 false alarm |
| [CausalStructures.jl](https://github.com/BjarkeHautop/CausalStructures.jl) | [`55646e2`](https://github.com/BjarkeHautop/CausalStructures.jl/commit/55646e2c16a06c1926380ff7a1111a9888fbfaba) (1.1.2-DEV) | 645 | 5 | 6 (6) | Trim-compatible; 6 false alarms |

Uncovered counts the public functions and types that no recorded call reaches directly, so
their trim compatibility is not checked. Their code may still run during the tests, inside
other calls. A direct call can also be missed when a compiled test helper makes it, or
dropped when an argument type is abstract or defined in the test files.

A signature only records types, so a call written as `f(x; Ptype = Float32)` is checked as
"some `DataType`". The `[value-dependent]` tag marks reports that may come from this. Thus
such a report may or may not be a false alarm, and we verify this by compiling the same call
with a literal value under `--trim=safe`.

## Sugiyama.jl

All public names are covered and 16 of the 17 signatures pass the trim verifier. They
include calls through a layout object such as
`(::Sugiyama.SugiyamaLayout{Float64, Float64})(::Array{Int64, 2})`, and sparse-matrix
inputs that the package's hand-written trim entry does not exercise.

The only report comes from the `Ptype` keyword, which picks the output point type. Passed
as a runtime `DataType`, the layout's type cannot be inferred. Written with a literal, as
in `SugiyamaLayout(; Ptype = Float32)`, it compiles. The package's own
[TrimCheck workflow](https://github.com/BjarkeHautop/Sugiyama.jl/blob/main/.github/workflows/TrimCheck.yml)
compiles exactly that call and passes.

Suggested `test/trim-allow.txt`:

```text
# Ptype is a literal type in real calls; only the recorded DataType fails.
Sugiyama.SugiyamaLayout(; Ptype::DataType)
```

## CausalStructures.jl

Five public names are uncovered. The tests never mention `RequiredEdge` or
`uniform_dag_counts`. They use `CausalEdge` and `ForbiddenEdge` values, but get them from
other functions and never call the constructors themselves. `Estimand` appears only as a
type, as in `one(Estimand)` and `Estimand[]`.

All six reports come from the `class` keyword of `generate_graph`, which picks the graph
type to return. Passed as a runtime `DataType`, the return type cannot be inferred.
Written with a literal, as in `generate_graph(10; p = 0.3, class = ADMG, latents = 2)`, it
compiles, with or without an explicit RNG. The package's own
[TrimCheck workflow](https://github.com/BjarkeHautop/CausalStructures.jl/blob/main/.github/workflows/TrimCheck.yml)
compiles both forms and passes.

```text
# class is a literal type in real calls; only the recorded DataType fails.
r"^CausalStructures\.generate_graph\(.*class::DataType"
```
