# TrimTrace

[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://BjarkeHautop.github.io/TrimTrace.jl/stable)
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://BjarkeHautop.github.io/TrimTrace.jl/dev)
[![Test workflow status](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/BjarkeHautop/TrimTrace.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/BjarkeHautop/TrimTrace.jl)
[![Lint workflow Status](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

Check that your package's public API compiles under `juliac --trim=safe`, without writing
the calls by hand.

TrimTrace runs your test suite under `--trace-compile`, keeps the concrete signatures of
calls into the package's public names (positional, keyword and constructor calls), and
compiles them as trim entry points with [JuliaC](https://github.com/JuliaLang/JuliaC.jl).
Every verifier error is attributed to the recorded signature it was reached from.

Requires Julia 1.12 or newer.

## Usage

Record once, and again whenever the tests change:

```julia
using TrimTrace, MyPackage

sigs = record(MyPackage)                 # runs test/runtests.jl in a child process
write_signatures("test/trim-signatures.txt", sigs)
uncovered(MyPackage, sigs)               # public names the trace never saw
```

Check the stored signatures, for example in CI:

```julia
result = check(MyPackage, "test/trim-signatures.txt"; allow = "test/trim-allow.txt")
display(result)
passed(result) || exit(1)
```

```text
TrimTrace check failed: 171 errors (7 value-dependent), 0 warnings, 0 allowed
  148 x CausalStructures.BackgroundKnowledge(::CausalStructures.CausalEdge)
  1 x CausalStructures.DAG(::CausalStructures.CausalEdge, ::CausalStructures.CausalEdge)
  1 x CausalStructures.generate_graph(::Int64; p::Float64, class::typeof(DataType)) [value-dependent]
  ...
Full juliac output: /tmp/jl_.../juliac.log
```

`allow` takes known failures, one per line in a file (or as a vector of strings and
`Regex`es), written as the report prints the signature, for example
`CausalStructures.layout(::CausalStructures.DAG)`. Allowed signatures are still compiled,
so the report lists allowlist entries that no longer match anything once they are fixed.

The signatures file has one `Tuple{...}` per line in sorted order, so re-recording shows up
as a diff. Delete a line to stop checking that signature, or pass `exclude` to `record`.

By default `check` builds against a generated project holding only the package and the
packages the signatures reference, so juliac does not instantiate test-only dependencies
such as plotting packages.

## What a recorded signature can and cannot tell you

- **Value-dependent calls.** A signature carries types, not values. Code that dispatches
  on a value, such as `generate_graph(n; class = CPDAG)` or `layout(g, :spring)` via
  `Val(method)`, only resolves when the argument is a compile-time constant at the call
  site. The check sees `class::DataType` and reports an error, tagged `[value-dependent]`.
  Such an error is real for callers that pass the value at run time and spurious for
  callers that pass a literal.
- **Missed calls.** `record` combines `--trace-compile` with `--trace-dispatch`. The first
  alone misses any call whose specialization was already compiled as the callee of an
  earlier call; the second logs every dynamically dispatched call, which covers top-level
  test code. A call made from inside a compiled test helper with inferable argument types
  is still missed; `uncovered` lists the public names no signature reaches.
- **Varargs.** A trailing `Vararg{A}` in the trace is checked as one `A`. Calls are made
  through generated wrapper functions with concrete argument types, like an ordinary call
  site, rather than marking the bare signature as an entry point.
- **Compile only.** The check compiles and verifies; it does not run the trimmed code.

## Related

[TrimCheck.jl](https://github.com/tz-lom/TrimCheck.jl) checks hand-listed calls by running
the trim verifier in a worker process instead of building with juliac.
