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

[`record_and_check`](@ref) runs `test/runtests.jl` with `--trace-dispatch`, keeps the calls
into public names of the package, writes them as trim entry points to an `entry.jl`, and
compiles that with `juliac --trim=safe`.

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
  1 x MyPackage.solve(::Int64; method::DataType) [value-dependent]
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

# Allow any call to solve that passes `method` as a DataType:
r"^MyPackage\.solve\(.*method::DataType"
```

To accept every `[value-dependent]` report instead, pass `allow_value_dependent = true`
to `record_and_check` (or to `write_ci_workflow` for the CI job).

## Limitations

### Only argument types are recorded

The trace holds the type of each argument, not its value. This matters when the value
decides what code runs, as with a type passed to pick a method:

```julia
struct Fast end
struct Exact end
halve(::Fast, x) = x / 2
halve(::Exact, x) = x // 2
solve(x; method::Type{M} = Fast) where {M} = halve(M(), x)

solve(10; method = Exact)  # checked as solve(::Int64; method::DataType)
```

The keyword value `Exact` is a type, and the type of a type is `DataType`, so that is all
the trace records. Knowing only that `method` is some `DataType`, the compiler can't tell
which `halve` to call, and the check fails, even though a caller writing
`solve(10; method = Exact)` compiles fine. These reports are tagged
`[value-dependent]`; allow them one at a time, or all at once with
`allow_value_dependent = true`.

### Calls made by other code are missed

A call is recorded only when the test code makes it. A function passed to other code is
called from inside that code, and that call is not recorded:

```julia
MyPkg.area(1.0)          # recorded as area(::Float64)
map(MyPkg.area, [1, 2])  # area(::Int64) is not recorded
```

[`uncovered`](@ref) lists the public names no recorded call reaches. To check such a
call, make it directly once in the tests.

### Some calls are dropped

A call is dropped when an argument type is defined in the test files, since the check
can't load it:

```julia
struct TestInput end
MyPkg.f(TestInput())  # dropped: TestInput only exists in the tests
```

A call is also dropped when an argument has an abstract type parameter, as in
`Vector{Any}`. Such containers usually come from shortcuts in the tests, and they fail
the trim check, because every use of an element is a dynamic call. Real callers pass
concretely typed containers:

```julia
MyPkg.total([1.0, 2.5])  # recorded as total(::Vector{Float64})

xs = []                  # a Vector{Any}
push!(xs, 1.0)
MyPkg.total(xs)          # dropped
```

If the package is meant to take such containers, keep these calls with
`abstract_params = true`.

Calls whose types Julia can't print back as valid code are dropped too
([julia#58756](https://github.com/JuliaLang/julia/issues/58756)).

### Varargs

Julia records a vararg call with the varargs collapsed, and TrimTrace checks it with a
single argument in their place:

```julia
total(xs::Int...) = sum(xs)
total(1, 2, 3)  # recorded as total(::Int64, ::Int64...), checked as total(::Int64, ::Int64)
```

See [Tested packages](90-tested-packages.md) for TrimTrace run on real packages, and the
[Reference](@ref reference) for every function and keyword.
