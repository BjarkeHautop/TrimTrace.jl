"""
    TrimTrace

Records the concrete call signatures a package's test suite makes into its public API and
checks that they compile under `juliac --trim=safe`.

[`record_and_check`](@ref) runs the whole pipeline, and [`write_ci_workflow`](@ref) sets
it up as a GitHub Actions job. The steps are:

 1. [`record`](@ref) runs the test suite under `--trace-compile` and `--trace-dispatch`
    and keeps the signatures of calls into public names of the package (positional,
    keyword and constructor calls, and calls to objects of its public types).
 2. [`uncovered`](@ref) lists the public names no recorded call reaches.
 3. [`check`](@ref) marks every signature as a trim entry point, compiles them with
    JuliaC, and reports the verifier errors per signature.
"""
module TrimTrace

using JuliaC: JuliaC
using TOML: TOML

export record, check, passed, uncovered, record_and_check, write_ci_workflow
public TrimError, TrimCheckResult

include("extract.jl")
include("record.jl")
include("signatures.jl")
include("check.jl")
include("ci.jl")

end
