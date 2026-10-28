"""
    record(pkg::Module; project, test_file, exclude = Symbol[], abstract_params = false,
           julia_args = String[]) -> Vector{Expr}

Run `test_file` in a fresh Julia process with `--trace-compile` and `--trace-dispatch` and
return the recorded public signatures of `pkg`, as [`extract_signatures`](@ref) does with
`exclude` and `abstract_params`.

`project` defaults to the package's `test` directory and `test_file` to
`test/runtests.jl`. A package that declares its test dependencies with `[extras]` and
`[targets]` instead of a `test/Project.toml` gets a generated test project holding the
package and those dependencies. `julia_args` are passed to the child process before the
test file. Failing tests only produce a warning, since the calls they made are still
valid signatures.

`--trace-compile` alone misses a call whose specialization was already compiled as the
callee of an earlier call; `--trace-dispatch` still logs it as long as the test makes the
call dynamically, as top-level test code does. A call made from inside a compiled test
helper function with inferable argument types is not dispatched dynamically and can be
missed.
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
        proc = run(ignorestatus(Cmd(cmd; dir = dirname(test_file))))
        if !success(proc)
            @warn "The tests exited with code $(proc.exitcode); keeping the calls they made"
        end
        return extract_signatures(pkg, filter(isfile, traces); exclude, abstract_params)
    finally
        foreach(trace -> rm(trace; force = true), traces)
    end
end

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
    deps = Dict{String,Any}(toml["name"] => toml["uuid"])
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
    run(`$(Base.julia_cmd()) --project=$dir -e "using Pkg; Pkg.instantiate()"`)
    return dir
end
