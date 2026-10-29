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

[`record_and_check`](@ref) runs `test/runtests.jl` with `--trace-compile` and
`--trace-dispatch`, keeps the calls into public names of the package, writes them as trim
entry points to an `entry.jl`, and compiles that with `juliac --trim=safe`.

### In CI

Generate the workflow once from the package root and commit it:

```julia
using TrimTrace
write_ci_workflow()   # writes .github/workflows/TrimTrace.yml
```

The job runs [`record_and_check`](@ref) on every push and pull request.

### Locally

Run the same check, or the steps on their own to look at what is recorded:

```julia
using TrimTrace, MyPackage

result = record_and_check(MyPackage; allow = "test/trim-allow.txt")
result.signatures            # the recorded calls

sigs = record(MyPackage)     # only record
uncovered(MyPackage, sigs)   # public names no recorded call reaches
check(MyPackage, sigs)       # only check
```

### Output and allowlist

The check fails when a recorded call does not trim:

```text
TrimTrace check failed: 2 errors (1 value-dependent), 0 warnings, 0 allowed
  1 x MyPackage.f(::Float64)
  1 x MyPackage.g(::Int64; kind::DataType) [value-dependent]
Signatures checked: 14 (listed in /tmp/jl_.../signatures.txt)
Full juliac output: /tmp/jl_.../juliac.log
```

An allowlist file holds accepted reports, each a signature as the report prints it or an
`r"..."` pattern. The CI job uses `test/trim-allow.txt` when it exists:

```text
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

See [Tested packages](90-tested-packages.md) for TrimTrace run on real packages, and the
[Reference](@ref reference) for every function and keyword.
