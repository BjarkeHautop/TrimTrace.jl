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

TrimTrace runs your tests with `--trace-dispatch`, keeps the concrete signatures of calls
into the package's public names, and compiles them as trim entry points with
[JuliaC](https://github.com/JuliaLang/JuliaC.jl).

## Installation

TrimTrace needs Julia 1.13 or later.

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

To show that your package is checked to be trim compatible with TrimTrace you can add the
badge to its README:

[![TrimTrace](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/BjarkeHautop/TrimTrace.jl/main/docs/src/assets/badge.json)](https://github.com/BjarkeHautop/TrimTrace.jl)

```markdown
[![TrimTrace](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/BjarkeHautop/TrimTrace.jl/main/docs/src/assets/badge.json)](https://github.com/BjarkeHautop/TrimTrace.jl)
```

### Locally

Run the same check, and look at what was recorded:

```julia
using TrimTrace, MyPackage

result = record_and_check(MyPackage; allow = "test/trim-allow.txt")
display(result)
result.signatures                         # the recorded calls
uncovered(MyPackage, result.signatures)   # public names no recorded call reaches
```

`record` and `check` can also be run as separate steps. To accept known failures, list
them in `test/trim-allow.txt`; see
[Output and allowlist](https://BjarkeHautop.github.io/TrimTrace.jl/dev/#Output-and-allowlist).

## Limitations

- [Only argument types are recorded](
  https://BjarkeHautop.github.io/TrimTrace.jl/dev/#Only-argument-types-are-recorded):
  a type or symbol passed as an argument is checked as any `DataType` or `Symbol`, which
  can fail where a literal would compile. These reports are tagged `[value-dependent]`.
- [Calls made by other code are missed](
  https://BjarkeHautop.github.io/TrimTrace.jl/dev/#Calls-made-by-other-code-are-missed):
  only calls the test code makes itself are recorded, not those made from inside, say,
  `map`.
- [Some calls are dropped](https://BjarkeHautop.github.io/TrimTrace.jl/dev/#Some-calls-are-dropped):
  calls with types defined in the tests, or with containers such as `Vector{Any}`.
- [Varargs](https://BjarkeHautop.github.io/TrimTrace.jl/dev/#Varargs) are checked with a single argument in place of the varargs.

## Documentation

See the [documentation](https://BjarkeHautop.github.io/TrimTrace.jl/dev) for more details.

## Related

[TrimCheck.jl](https://github.com/tz-lom/TrimCheck.jl) also checks calls with the trim
verifier, but the calls to check must be listed by hand. It runs the verifier directly in
a Julia process, which depends on compiler internals; TrimTrace compiles with
`juliac --trim=safe`.
