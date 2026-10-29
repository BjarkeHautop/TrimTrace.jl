# TrimTrace

[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://BjarkeHautop.github.io/TrimTrace.jl/stable)
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://BjarkeHautop.github.io/TrimTrace.jl/dev)
[![Test workflow status](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/BjarkeHautop/TrimTrace.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/BjarkeHautop/TrimTrace.jl)
[![Lint workflow Status](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/TrimTrace.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

Check that your package's public API compiles under `juliac --trim=safe`, using the calls
your test suite already makes instead of writing them by hand.

TrimTrace runs your tests with `--trace-compile` and `--trace-dispatch`, keeps the concrete
signatures of calls into the package's public names (including keyword and constructor
calls), and compiles them as trim entry points with
[JuliaC](https://github.com/JuliaLang/JuliaC.jl). Each verifier error is reported against
the signature it was reached from. Requires Julia 1.12+.

## Usage

```julia
using TrimTrace, MyPackage

# Record (rerun when the tests change); the file diffs cleanly, one signature per line.
sigs = record(MyPackage)
write_signatures("test/trim-signatures.txt", sigs)
uncovered(MyPackage, sigs)   # public names no recorded call reaches

# Check, e.g. in CI.
result = check(MyPackage, "test/trim-signatures.txt"; allow = "test/trim-allow.txt")
display(result)
passed(result) || exit(1)
```

```text
TrimTrace check failed: 2 errors (1 value-dependent), 0 warnings, 0 allowed
  1 x MyPackage.f(::Float64)
  1 x MyPackage.g(::Int64; kind::DataType) [value-dependent]
Full juliac output: /tmp/jl_.../juliac.log
```

The allowlist holds known failures, one signature per line as the report prints it (or
pass a vector of strings and `Regex`es). Entries that no longer match are reported as
stale.

## Limitations

- **Values are not recorded, only types.** If a test calls `g(10; kind = Foo)`, TrimTrace
  records "an `Int64` and some `DataType`", not `Foo` itself. Compiling that, the compiler
  cannot tell which type `kind` is, so trimming fails. A user who writes
  `g(10; kind = Foo)` in their own code is fine, because there the compiler sees `Foo`.
  These errors are tagged `[value-dependent]` and are often false alarms.
- **Some calls are missed.** TrimTrace sees calls by watching what Julia compiles and
  dispatches during the tests. If a test calls `f` from inside a helper such as
  `check(x) = f(x)`, the call to `f` can be compiled into `check` without being logged, so
  it is never checked. `uncovered` lists public names that were never seen at all, but not
  missing argument types for names that were.
- **Varargs.** A call to `f(xs...)` recorded as "any number of `Int64`s" is checked as a
  call with a single `Int64`.

## Related

[TrimCheck.jl](https://github.com/tz-lom/TrimCheck.jl) checks hand-listed calls by running
the trim verifier in a worker process instead of building with juliac.
