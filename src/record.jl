"""
    record(pkg::Module; project, test_file, exclude = Symbol[], julia_args = String[])
        -> Vector{Expr}

Run `test_file` in a fresh Julia process with `--trace-compile` and `--trace-dispatch` and
return the recorded public signatures of `pkg`, as [`extract_signatures`](@ref) does.

`project` defaults to the package's `test` directory and `test_file` to
`test/runtests.jl`. `julia_args` are passed to the child process before the test file.

`--trace-compile` alone misses a call whose specialization was already compiled as the
callee of an earlier call; `--trace-dispatch` still logs it as long as the test makes the
call dynamically, as top-level test code does. A call made from inside a compiled test
helper function with inferable argument types is not dispatched dynamically and can be
missed.
"""
function record(
    pkg::Module;
    project = joinpath(pkgdir(pkg), "test"),
    test_file = joinpath(pkgdir(pkg), "test", "runtests.jl"),
    exclude = Symbol[],
    julia_args = String[],
)
    traces = [tempname() * ".jl" for _ = 1:2]
    project = abspath(project)
    test_file = abspath(test_file)
    try
        julia = Base.julia_cmd()
        trace_args = ["--trace-compile=$(traces[1])", "--trace-dispatch=$(traces[2])"]
        cmd = `$julia --project=$project $trace_args $julia_args $test_file`
        run(Cmd(cmd; dir = dirname(test_file)))
        return extract_signatures(pkg, filter(isfile, traces); exclude)
    finally
        foreach(trace -> rm(trace; force = true), traces)
    end
end
