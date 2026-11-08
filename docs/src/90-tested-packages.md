# Tested packages

I ran TrimTrace on two of my own packages that already work with `--trim=safe`, since
each has a hand-written trim check to compare against. This page shows what TrimTrace
found, and which of the reports turned out to be false alarms that belong in the package's
allowlist.

All runs used Julia 1.13.2 and JuliaC 0.3.12, on 2026-11-08.

## How the runs were made

I checked out each package, instantiated its test environment, and ran
[`record_and_check`](@ref) on its own test suite:

```julia
using TrimTrace, Sugiyama

result = record_and_check(Sugiyama)
display(result)
uncovered(Sugiyama, result.signatures)
```

CausalStructures was run the same way. With the allowlists suggested below saved as
`test/trim-allow.txt` and passed as `allow = "test/trim-allow.txt"`, both packages pass.

## Results

| Package | Tested at | Signatures | Uncovered | Errors (value-dependent) | Verdict |
|---|---|---|---|---|---|
| [Sugiyama.jl](https://github.com/BjarkeHautop/Sugiyama.jl) | [`ff0c4f6`](https://github.com/BjarkeHautop/Sugiyama.jl/commit/ff0c4f60846dcc5cb39961ce5aae092106a1f7f8) (v1.0.1) | 18 | 0 | 1 (1) | Trim-compatible; 1 false alarm |
| [CausalStructures.jl](https://github.com/BjarkeHautop/CausalStructures.jl) | [`dd8aaf4`](https://github.com/BjarkeHautop/CausalStructures.jl/commit/dd8aaf435823d7a9a2b004471c7a13df7d9d2755) (1.1.2-DEV) | 645 | 5 | 6 (6) | Trim-compatible; 6 false alarms |

**Uncovered** is the number of public functions and types that no recorded call reaches
directly, so TrimTrace never checks them. Their code may well run during the tests, just
inside some other call. A direct call can also slip through if a compiled test helper makes
it, or get dropped if one of its argument types is abstract or defined in the test files.

**Value-dependent** reports need a closer look. TrimTrace records only the types of the
arguments, so a call written as `f(x; Ptype = Float32)` is checked as if `Ptype` were
"some `DataType`". That is often harder for the compiler than the real call. To tell
whether such a report is a genuine problem, I compiled the same call with the literal
value under `--trim=safe`.

## Sugiyama.jl

Every public name is covered, and 17 of the 18 signatures pass the trim verifier. These
include calls through a layout object, such as
`(::Sugiyama.SugiyamaLayout{Float64, Float64})(::Array{Int64, 2})`, a `Graphs.SimpleDiGraph`
input going through the Graphs extension, and sparse-matrix inputs that the package's own
hand-written trim entry point doesn't cover.

The one report comes from the `Ptype` keyword, which chooses the output point type. When
it arrives as a runtime `DataType`, the compiler can't work out the layout's type. Written
with a literal, as in `SugiyamaLayout(; Ptype = Float32)`, it compiles fine, and the
package's own
[TrimCheck workflow](https://github.com/BjarkeHautop/Sugiyama.jl/blob/main/.github/workflows/TrimCheck.yml)
compiles exactly that call. So this one is a false alarm.

Suggested `test/trim-allow.txt`:

```text
# Ptype is a literal type in real calls; only the recorded DataType fails.
Sugiyama.SugiyamaLayout(; Ptype::DataType)
```

## CausalStructures.jl

Five public names are uncovered. The tests never mention `RequiredEdge` or
`uniform_dag_counts` at all. They do use `CausalEdge` and `ForbiddenEdge` values, but get
them from other functions rather than calling the constructors. `Estimand` only shows up
as a type, as in `one(Estimand)` and `Estimand[]`.

All six reports come from the `class` keyword of `generate_graph`, which chooses the kind
of graph to return. As a runtime `DataType`, the compiler can't infer the return type.
Written with a literal, as in `generate_graph(10; p = 0.3, class = ADMG, latents = 2)`, it
compiles, with or without an explicit RNG, and the package's own
[TrimCheck workflow](https://github.com/BjarkeHautop/CausalStructures.jl/blob/main/.github/workflows/TrimCheck.yml)
checks both forms. These are false alarms too.

Suggested `test/trim-allow.txt`:

```text
# class is a literal type in real calls; only the recorded DataType fails.
r"^CausalStructures\.generate_graph\(.*class::DataType"
```
