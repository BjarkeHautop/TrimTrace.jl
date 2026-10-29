"""
    record(pkg::Module; project, test_file, exclude = Symbol[], abstract_params = false,
           julia_args = String[]) -> Vector{Expr}

Run the test suite of `pkg` with tracing on and return the public signatures it called.

The test file runs in a fresh Julia process with `--trace-compile` and `--trace-dispatch`,
and the traces are filtered as [`extract_signatures`](@ref) does.

# Arguments
- `pkg::Module`: the package under test.

# Keywords
- `project`: the test environment. Defaults to the package's `test` directory. A package
  that declares its test dependencies with `[extras]` and `[targets]` instead of a
  `test/Project.toml` gets a generated test project holding the package, its
  dependencies and those test dependencies.
- `test_file`: the file to run, by default `test/runtests.jl`.
- `exclude = Symbol[]`: passed to [`extract_signatures`](@ref).
- `abstract_params = false`: passed to [`extract_signatures`](@ref).
- `julia_args = String[]`: arguments passed to the child process before the test file.

# Returns
The recorded signatures, sorted and deduplicated.

# Notes
Failing tests only produce a warning, since the calls they made are still valid
signatures.

`--trace-compile` alone misses a call whose specialization was already compiled as the
callee of an earlier call; `--trace-dispatch` still logs it as long as the test makes the
call dynamically, as top-level test code does. A call made from inside a compiled test
helper function with inferable argument types is not dispatched dynamically and can be
missed.

# Examples
```jldoctest
julia> using TrimFixture  # the demo package in test/fixtures

julia> record(TrimFixture; project = pkgdir(TrimFixture))
6-element Vector{Expr}:
 :(Tuple{TrimFixture.Scaler, Int64})
 :(Tuple{Type{TrimFixture.Box}, Int64})
 :(Tuple{Type{TrimFixture.Scaler}, Int64})
 :(Tuple{typeof(Core.kwcall), NamedTuple{(:factor,), Tuple{Int64}}, typeof(TrimFixture.scaled), Int64})
 :(Tuple{typeof(TrimFixture.stable), TrimFixture.Box})
 :(Tuple{typeof(TrimFixture.unstable), Int64})
```
"""
function record(
    pkg::Module;
    project = _default_test_project(pkg),
    test_file = joinpath(pkgdir(pkg), "test", "runtests.jl"),
    exclude = Symbol[],
    abstract_params = false,
    julia_args = String[],
)
    traces = [tempname() * ".jl" for _ = 1:2]
    project = abspath(project)
    test_file = abspath(test_file)
    try
        julia = Base.julia_cmd()
        trace_args = ["--trace-compile=$(traces[1])", "--trace-dispatch=$(traces[2])"]
        cmd = `$julia --project=$project $trace_args $julia_args $test_file`
        proc = run(ignorestatus(Cmd(_clean_env(cmd); dir = dirname(test_file))))
        if !success(proc)
            @warn "The tests exited with code $(proc.exitcode); keeping the calls they made"
        end
        sigs = extract_signatures(pkg, filter(isfile, traces); exclude, abstract_params)
        isempty(sigs) && @warn "No public calls of $pkg were recorded"
        return sigs
    finally
        foreach(trace -> rm(trace; force = true), traces)
    end
end

# Drops the load path and project inherited from the calling process, as set by `Pkg.test`,
# so the child process sees only its `--project` and the standard library.
_clean_env(cmd) =
    setenv(cmd, filter(p -> p.first ∉ ("JULIA_LOAD_PATH", "JULIA_PROJECT"), ENV))

function _default_test_project(pkg::Module)
    test_dir = joinpath(pkgdir(pkg), "test")
    isfile(joinpath(test_dir, "Project.toml")) && return test_dir
    return _legacy_test_project(pkgdir(pkg))
end

# Builds and instantiates a test project from the `[extras]` and `[targets]` sections, with
# the package itself referenced by path.
function _legacy_test_project(pkg_path::AbstractString)
    toml = TOML.parsefile(joinpath(pkg_path, "Project.toml"))
    extras = get(toml, "extras", Dict{String,Any}())
    targets = get(get(toml, "targets", Dict{String,Any}()), "test", String[])
    compat = get(toml, "compat", Dict{String,Any}())
    # `Pkg.test` lets the tests load the package's own dependencies as well.
    deps = Dict{String,Any}(get(toml, "deps", Dict{String,Any}()))
    deps[toml["name"]] = toml["uuid"]
    for name in targets
        deps[name] = extras[name]
    end
    project = Dict{String,Any}(
        "deps" => deps,
        "sources" => Dict(toml["name"] => Dict("path" => pkg_path)),
        "compat" => Dict(k => v for (k, v) in compat if haskey(deps, k)),
    )
    dir = mktempdir()
    open(io -> TOML.print(io, project), joinpath(dir, "Project.toml"), "w")
    run(_clean_env(`$(Base.julia_cmd()) --project=$dir -e "using Pkg; Pkg.instantiate()"`))
    return dir
end
