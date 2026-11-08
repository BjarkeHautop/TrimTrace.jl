# TrimTrace

<!---
[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://BjarkeHautop.github.io/TrimTrace.jl/stable)
-->
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://BjarkeHautop.github.io/TrimTrace.jl/dev)
[![Test workflow status](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/BjarkeHautop/TrimTrace.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/BjarkeHautop/TrimTrace.jl)
[![Lint workflow Status](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

Check that your package's public API compiles under `juliac --trim=safe` by using the calls
your test suite makes.

TrimTrace runs your tests with `--trace-compile` and `--trace-dispatch`, keeps the concrete
signatures of calls into the package's public names, and compiles them as trim entry points with
[JuliaC](https://github.com/JuliaLang/JuliaC.jl).

## Installation

TrimTrace needs Julia 1.12 or later.

```julia
using Pkg
Pkg.add(url = "https://github.com/BjarkeHautop/TrimTrace.jl")
```

## Usage

`record_and_check` runs `test/runtests.jl` with tracing on, turns the recorded calls into
an `entry.jl` of trim entry points, and compiles it with `juliac --trim=safe`.

### In CI

From the package root, generate the workflow once and commit it:

```julia
using TrimTrace
write_ci_workflow()   # writes .github/workflows/TrimTrace.yml
```

The job runs `record_and_check` on every push and pull request and fails when a recorded
call does not trim.

### Locally

Run the same check, and look at what was recorded:

```julia
using TrimTrace, MyPackage

result = record_and_check(MyPackage; allow = "test/trim-allow.txt")
display(result)
result.signatures                         # the recorded calls
uncovered(MyPackage, result.signatures)   # public names no recorded call reaches
```

`record` and `check` can also be run as separate steps.

### Output and allowlist

The result lists the verifier reports, grouped by the signature they were reached from:

```text
TrimTrace check failed: 2 errors (1 value-dependent), 0 warnings, 0 allowed
  1 x MyPackage.f(::Float64)
  1 x MyPackage.g(::Int64; kind::DataType) [value-dependent]
Signatures checked: 14 (listed in /tmp/jl_.../signatures.txt)
Full juliac output: /tmp/jl_.../juliac.log
```

An allowlist file holds known failures, one signature per line as the report prints it,
or a pattern written as `r"..."` that covers several signatures at once (or pass a vector
of strings and `Regex`es). The CI job uses `test/trim-allow.txt` when it exists:

```text
# test/trim-allow.txt
MyPackage.f(::Float64)
r"^MyPackage\.g\(.*kind::DataType"
```

## Limitations

- **Only types are recorded.** A test calling `g(10; kind = Foo)` is checked
  as `g(::Int64; kind::DataType)`, which often fails to trim even though a caller writing
  `kind = Foo` compiles fine. These reports are tagged `[value-dependent]`.
- **Some calls are missed.** A call made from inside a compiled test helper can be
  compiled into the helper without being logged. [`uncovered`](@ref) lists the public
  names no recorded call reaches.
- **Varargs** are checked as a call with a single argument of the recorded type.

## Documentation

See the [documentation](https://BjarkeHautop.github.io/TrimTrace.jl/dev) for more details.

## Related

[TrimCheck.jl](https://github.com/tz-lom/TrimCheck.jl) also checks calls with the trim
verifier, but the calls to check must be listed by hand. It runs the verifier directly in
a Julia process, which depends on compiler internals; TrimTrace compiles with
`juliac --trim=safe`.
