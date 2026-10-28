"""
    TrimTrace

Records the concrete call signatures a package's test suite makes into its public API and
checks that they compile under `juliac --trim=safe`.

The workflow is:

 1. [`record`](@ref) runs the test suite under `--trace-compile` and keeps the signatures
    of calls into public names of the package (positional, keyword, and constructor calls).
 2. [`write_signatures`](@ref) stores them as a sorted text file to commit next to the
    tests.
 3. [`check`](@ref) marks every stored signature as a trim entry point, compiles them with
    JuliaC, and reports the verifier errors per signature.
"""
module TrimTrace

using JuliaC: JuliaC
using TOML: TOML

export record,
    extract_signatures,
    write_signatures,
    read_signatures,
    uncovered,
    entry_file,
    check,
    passed
public TrimError, TrimCheckResult, parse_juliac_log

include("extract.jl")
include("record.jl")
include("signatures-file.jl")
include("check.jl")

end
