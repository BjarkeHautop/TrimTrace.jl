```@meta
CurrentModule = TrimTrace
```

# TrimTrace

TrimTrace checks that a package's public API compiles under `juliac --trim=safe`, using
the calls its test suite already makes. It records the concrete signatures of those calls,
compiles each one as a trim entry point with [JuliaC](https://github.com/JuliaLang/JuliaC.jl),
and reports every verifier error against the signature it was reached from.

## Installation

TrimTrace needs Julia 1.12 or later.

```julia
using Pkg
Pkg.add(url = "https://github.com/BjarkeHautop/TrimTrace.jl")
```

## Workflow

Record the signatures once and commit them next to the tests:

```julia
using TrimTrace, MyPackage

sigs = record(MyPackage)
write_signatures("test/trim-signatures.txt", sigs)
uncovered(MyPackage, sigs)   # public names no recorded call reaches
```

[`record`](@ref) runs `test/runtests.jl` with `--trace-compile` and `--trace-dispatch` and
keeps the calls into public names of the package. Calls with abstract argument types, or
with types defined in the test files, are dropped. Record again when the tests change.

Then check the file, typically as a separate CI job, since compiling takes a while:

```julia
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

The allowlist can holds accepted report, each a signature as the report prints it or an
`r"..."` pattern:

```text
MyPackage.f(::Float64)
r"^MyPackage\.g\(.*kind::DataType"
```

## Limitations

- **Only types are recorded, not values.** A test calling `g(10; kind = Foo)` is checked
  as `g(::Int64; kind::DataType)`, which often fails to trim even though a caller writing
  `kind = Foo` compiles fine. These reports are tagged `[value-dependent]`.
- **Some calls are missed.** A call made from inside a compiled test helper can be
  compiled into the helper without being logged.
- **Varargs** are checked as a call with a single argument of the recorded type.

See [Tested packages](90-tested-packages.md) for TrimTrace run on real packages, and the
[Reference](@ref reference) for every function and keyword.
