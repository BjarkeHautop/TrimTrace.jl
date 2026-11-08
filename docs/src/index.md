```@meta
CurrentModule = TrimTrace
```

# TrimTrace

TrimTrace checks that a package's public API compiles under `juliac --trim=safe`, using
the calls its test suite already makes. It records the concrete signatures of those calls,
compiles each one as a trim entry point with [JuliaC](https://github.com/JuliaLang/JuliaC.jl),
and reports every verifier error against the signature it was reached from.

## Installation

TrimTrace needs Julia 1.13 or later.

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

To show that your package is checked to be trim compatible with TrimTrace you can add the badge
[![TrimTrace](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/BjarkeHautop/TrimTrace.jl/main/docs/src/assets/badge.json)](https://github.com/BjarkeHautop/TrimTrace.jl)
to its README:

```markdown
[![TrimTrace](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/BjarkeHautop/TrimTrace.jl/main/docs/src/assets/badge.json)](https://github.com/BjarkeHautop/TrimTrace.jl)
```

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

To accept a failure you cannot fix yet, or a `[value-dependent]` report that real callers
would not hit (see Limitations below), add it to an allowlist file. Allowed reports are
counted in the summary but no longer fail the check. Each line of the file is either

- a signature copied exactly as the report prints it, or
- a regular expression written as `r"..."`, which allows every signature it matches.

Blank lines and lines starting with `#` are ignored. The CI job reads
`test/trim-allow.txt` if it exists; locally, pass the path as `allow` (see above).

```text
# test/trim-allow.txt

# Allow exactly this signature:
MyPackage.f(::Float64)

# Allow any call to g that passes `kind` as a DataType:
r"^MyPackage\.g\(.*kind::DataType"
```

To accept every `[value-dependent]` report instead, pass `allow_value_dependent = true`
to `record_and_check` (or to `write_ci_workflow` for the CI job).

## Limitations

- **Only types are recorded.** A test calling `g(10; kind = Foo)` is checked
  as `g(::Int64; kind::DataType)`, which often fails to trim even though a caller writing
  `kind = Foo` compiles fine. These reports are tagged `[value-dependent]`; allow them
  one by one or all at once with `allow_value_dependent = true`.
- **Some calls are missed.** A call made from inside a compiled test helper can be
  compiled into the helper without being logged. [`uncovered`](@ref) lists the public
  names no recorded call reaches.
- **Varargs** are checked as a call with a single argument of the recorded type.

See [Tested packages](90-tested-packages.md) for TrimTrace run on real packages, and the
[Reference](@ref reference) for every function and keyword.
