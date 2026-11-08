@testmodule Fixture begin
    const DIR = joinpath(@__DIR__, "fixtures", "TrimFixture")
    DIR in LOAD_PATH || push!(LOAD_PATH, DIR)
    using TrimFixture: TrimFixture

    function trace_file(lines)
        path = tempname() * ".jl"
        write(path, join(lines, '\n'))
        return path
    end
end

@testitem "_extract_signatures keeps concrete public calls" tags = [:unit] setup = [Fixture] begin
    using .Fixture: TrimFixture
    struct LocalType end
    trace = Fixture.trace_file([
        "precompile(Tuple{typeof(TrimFixture.stable), TrimFixture.Box})",
        "precompile(Tuple{Type{TrimFixture.Box}, Int64})",
        "precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:factor,), Tuple{Int64}}, typeof(TrimFixture.scaled), Int64})",
        "precompile(Tuple{typeof(TrimFixture.unstable), Int64, Vararg{Int64}})",
        "precompile(Tuple{TrimFixture.Scaler, Int64})",
        # Internal name, abstract argument, test-local type, unrelated function, noise.
        "precompile(Tuple{typeof(TrimFixture._internal), Int64})",
        "precompile(Tuple{typeof(TrimFixture.stable), Any})",
        "precompile(Tuple{typeof(TrimFixture.stable), Main.LocalType})",
        "precompile(Tuple{typeof(Base.sum), Array{Int64, 1}})",
        "precompile(Tuple{Base.RefValue{Int64}, Int64})",
        "# comment line",
        "precompile(Tuple{typeof(TrimFixture.stable), TrimFixture.Box})",
    ])
    sigs = TrimTrace._extract_signatures(TrimFixture, [trace])
    @test string.(sigs) == [
        "Tuple{TrimFixture.Scaler, Int64}",
        "Tuple{Type{TrimFixture.Box}, Int64}",
        "Tuple{typeof(Core.kwcall), NamedTuple{(:factor,), Tuple{Int64}}, typeof(TrimFixture.scaled), Int64}",
        "Tuple{typeof(TrimFixture.stable), TrimFixture.Box}",
        "Tuple{typeof(TrimFixture.unstable), Int64, Int64}",
    ]
    @test length(
        TrimTrace._extract_signatures(TrimFixture, [trace]; exclude = [:stable, :Box]),
    ) == 3
end

@testitem "_extract_signatures drops abstract type parameters" tags = [:unit] setup =
    [Fixture] begin
    using .Fixture: TrimFixture
    trace = Fixture.trace_file([
        "precompile(Tuple{typeof(TrimFixture.stable), Array{Any, 1}})",
        "precompile(Tuple{typeof(TrimFixture.stable), Array{(NamedTuple{names, T} where T <: Tuple) where names, 1}})",
        "precompile(Tuple{typeof(TrimFixture.stable), Array{Array{Real, 1}, 1}})",
        "precompile(Tuple{typeof(Core.kwcall), NamedTuple{(:factor,), Tuple{Array{Any, 1}}}, typeof(TrimFixture.scaled), Int64})",
        "precompile(Tuple{typeof(TrimFixture.stable), Array{Union{Nothing, Int64}, 1}})",
        "precompile(Tuple{typeof(TrimFixture.stable), Base.RefValue{Type{Int64}}})",
    ])
    @test string.(TrimTrace._extract_signatures(TrimFixture, [trace])) == [
        "Tuple{typeof(TrimFixture.stable), Array{Union{Nothing, Int64}, 1}}",
        "Tuple{typeof(TrimFixture.stable), Base.RefValue{Type{Int64}}}",
    ]
    @test length(
        TrimTrace._extract_signatures(TrimFixture, [trace]; abstract_params = true),
    ) == 6
end

@testitem "uncovered" tags = [:unit] setup = [Fixture] begin
    using .Fixture: TrimFixture
    sigs = [
        :(Tuple{typeof(TrimFixture.stable),TrimFixture.Box}),
        :(Tuple{Type{TrimFixture.Box},Int64}),
        :(Tuple{
            typeof(Core.kwcall),
            NamedTuple{(:factor,),Tuple{Int64}},
            typeof(TrimFixture.scaled),
            Int64,
        }),
        :(Tuple{TrimFixture.Scaler,Int64}),
    ]
    @test uncovered(TrimFixture, sigs) == [:uncalled, :unstable]
    @test uncovered(TrimFixture, sigs; exclude = [:uncalled]) == [:unstable]
    # A constructor recorded through a `where` clause still names its type.
    @test TrimTrace._signature_callee(:(Tuple{Type{M.T{P} where P},Int64})) === :T
    @test TrimTrace._signature_callee(:(Tuple{M.T{Int64},Int64})) === :T
end

@testitem "_entry_file wrappers make the recorded calls" tags = [:unit] setup = [Fixture] begin
    using .Fixture: TrimFixture
    sigs = [
        :(Tuple{Type{TrimFixture.Box},Int64}),
        :(Tuple{
            typeof(Core.kwcall),
            NamedTuple{(:factor,),Tuple{Int64}},
            typeof(TrimFixture.scaled),
            Int64,
        }),
        :(Tuple{typeof(TrimFixture.stable),TrimFixture.Box}),
        :(Tuple{TrimFixture.Scaler,Int64}),
    ]
    path = TrimTrace._entry_file(tempname() * ".jl", TrimFixture, sigs)
    src = read(path, String)
    @test occursin("import TrimFixture\n", src)
    @test occursin(
        "Base.Experimental.entrypoint(entry_2, (NamedTuple{(:factor,), Tuple{Int64}}, Int64))",
        src,
    )
    # `entrypoint` is a no-op outside of output generation, so the file can be loaded and the
    # wrappers called directly.
    entry = Module()
    Core.eval(entry, :(const TrimFixture = $TrimFixture))
    Base.include(entry, path)
    @test entry.TrimTraceEntry.entry_1(3) == TrimFixture.Box(3)
    @test entry.TrimTraceEntry.entry_2((; factor = 5), 3) == 15
    @test entry.TrimTraceEntry.entry_3(TrimFixture.Box(1)) == 2
    @test entry.TrimTraceEntry.entry_4(TrimFixture.Scaler(2), 3) == 6
end

@testitem "signature labels" tags = [:unit] begin
    sig = :(Tuple{
        typeof(Core.kwcall),
        NamedTuple{(:a, :b),Tuple{Int64,Symbol}},
        typeof(M.f),
        String,
    })
    @test TrimTrace._signature_string(sig) == "M.f(::String; a::Int64, b::Symbol)"
    @test TrimTrace._signature_string(:(Tuple{Type{M.T},Int64,Int64})) ==
          "M.T(::Int64, ::Int64)"
    @test TrimTrace._signature_string(:(Tuple{typeof(M.g)})) == "M.g()"
    ntuple_sig =
        :(Tuple{typeof(Core.kwcall),NamedTuple{(:a, :b, :c),NTuple{3,Float64}},typeof(M.f)})
    @test TrimTrace._signature_string(ntuple_sig) ==
          "M.f(; a::Float64, b::Float64, c::Float64)"
    @test TrimTrace._signature_string(:(Tuple{M.T{Int64},String})) ==
          "(::M.T{Int64})(::String)"
    where_sig = :(Tuple{
        typeof(Core.kwcall),
        NamedTuple{(:P,),Tuple{typeof(DataType)}},
        Type{(M.T{P,Q} where {Q}) where P},
    })
    @test TrimTrace._signature_string(where_sig) == "M.T(; P::DataType)"
end

@testitem "parse_juliac_log" tags = [:unit] begin
    log = tempname()
    write(
        log,
        """
        Compiling...
        Verifier error #1: ignored header that is not a report
        Error #1: unresolved call from statement string(
          (…)::Any
        )::String

        Stacktrace:
         [1] unstable(i::Int64)
           @ TrimFixture src/TrimFixture.jl:15 [inlined]
         [2] entry_4(a1::Int64)
           @ Main.TrimTraceEntry entry.jl:20
         [3] main(args::Vector{String})
           @ Main.TrimTraceEntry entry.jl:40

        Warning #1: unresolved call from statement generate(
          getfield(::@NamedTuple{class::DataType}, :class::Symbol)::DataType
        )::Any

        Trim verify finished with 1 errors, 1 warnings.
        """,
    )
    errs = TrimTrace._parse_juliac_log(log)
    @test length(errs) == 2
    @test errs[1].kind === :error
    @test errs[1].entry == "entry_4(a1::Int64)"
    @test !errs[1].value_dependent
    @test errs[2].kind === :warning
    @test errs[2].entry == "unresolved call from statement generate("
    @test errs[2].value_dependent
    sigs = [:(Tuple{typeof(M.f)}) for _ = 1:3]
    push!(sigs, :(Tuple{typeof(TrimFixture.unstable),Int64}))
    @test TrimTrace._relabel(errs[1], sigs).entry == "TrimFixture.unstable(::Int64)"
    # A value-dependent report stays tagged only when the signature passes such a value.
    value_err = TrimTrace.TrimError(:error, "", "entry_1(a1::Int64)", true)
    @test !TrimTrace._relabel(value_err, [:(Tuple{typeof(M.f),Int64})]).value_dependent
    @test TrimTrace._relabel(value_err, [:(Tuple{typeof(M.f),Symbol})]).value_dependent
    kw_sig =
        :(Tuple{typeof(Core.kwcall),NamedTuple{(:k,),Tuple{typeof(DataType)}},typeof(M.f)})
    @test TrimTrace._relabel(value_err, [kw_sig]).value_dependent
end

@testitem "allowlist file with patterns" tags = [:unit] begin
    path = tempname()
    write(
        path,
        """
        # comment
        M.f(::Float64)
        r"^M\\.g\\(.*kind::DataType"
        """,
    )
    allow = TrimTrace._read_allowlist(path)
    @test allow[1] == "M.f(::Float64)"
    @test allow[2] isa Regex
    @test TrimTrace._matches(allow[2], "M.g(::Int64; kind::DataType)")
    @test TrimTrace._matches(allow[2], "M.g(; n::Int64, kind::DataType)")
    @test !TrimTrace._matches(allow[2], "M.g(::Int64)")
    @test !TrimTrace._matches(allow[1], "M.f(::Int64)")
end

@testitem "failed compile without reports shows the juliac output" tags = [:unit] begin
    log = tempname()
    write(log, "Compiling...\nERROR: linker not found\n")
    result = TrimTrace.TrimCheckResult(
        false,
        TrimTrace.TrimError[],
        TrimTrace.TrimError[],
        Expr[],
        log,
    )
    @test !passed(result)
    shown = sprint(show, MIME"text/plain"(), result)
    @test occursin("juliac failed without verifier reports", shown)
    @test occursin("ERROR: linker not found", shown)
end

@testitem "check rejects an empty signature list" tags = [:unit] setup = [Fixture] begin
    using .Fixture: TrimFixture
    @test_throws ArgumentError check(TrimFixture, Expr[])
end

@testitem "write_ci_workflow" tags = [:unit] setup = [Fixture] begin
    path = write_ci_workflow(Fixture.DIR; path = tempname() * ".yml", julia = "1.13")
    yml = read(path, String)
    @test occursin("version: \"1.13\"", yml)
    @test occursin("using TrimTrace, TrimFixture", yml)
    @test occursin("record_and_check(TrimFixture; allow)", yml)
    @test occursin("\${{ github.workflow }}", yml)
    @test occursin("Pkg.develop(path = \".\")", yml)
    # The fixture has no test/Project.toml, so `record` generates its test project.
    @test !occursin("--project=test", yml)
end

@testitem "legacy test project includes the package dependencies" tags = [:unit] begin
    using TOML
    pkg = mktempdir()
    write(
        joinpath(pkg, "Project.toml"),
        """
        name = "LegacyPkg"
        uuid = "5a1d6f3c-1b7e-4c41-9f1a-2a6b3c4d5e6f"

        [deps]
        Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

        [extras]
        Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

        [targets]
        test = ["Test"]
        """,
    )
    mkpath(joinpath(pkg, "src"))
    write(joinpath(pkg, "src", "LegacyPkg.jl"), "module LegacyPkg end")
    dir = TrimTrace._legacy_test_project(pkg)
    deps = TOML.parsefile(joinpath(dir, "Project.toml"))["deps"]
    @test sort!(collect(keys(deps))) == ["LegacyPkg", "Random", "Test"]
end

@testitem "record and check the fixture package" tags = [:integration, :slow] setup =
    [Fixture] begin
    using .Fixture: TrimFixture
    sigs = record(
        TrimFixture;
        project = Fixture.DIR,
        test_file = joinpath(Fixture.DIR, "test", "runtests.jl"),
    )
    @test "Tuple{typeof(TrimFixture.unstable), Int64}" in string.(sigs)
    @test uncovered(TrimFixture, sigs) == [:uncalled]

    result = check(TrimFixture, sigs; project = Fixture.DIR)
    # Surface the juliac output in the test log if juliac itself failed.
    isempty(result.errors) && display(result)
    @test !result.compiled
    @test !passed(result)
    entries = unique(err.entry for err in result.errors if err.kind === :error)
    @test entries == ["TrimFixture.unstable(::Int64)"]
    @test occursin("TrimTrace check failed", sprint(show, MIME"text/plain"(), result))

    allow_file = tempname()
    write(allow_file, "# known failure\nTrimFixture.unstable(::Int64)\n")
    result = check(TrimFixture, sigs; project = Fixture.DIR, allow = allow_file)
    @test passed(result)
    @test isempty(result.errors)
    @test unique(err.entry for err in result.allowed) == ["TrimFixture.unstable(::Int64)"]
    shown = sprint(show, MIME"text/plain"(), result)
    @test occursin("TrimTrace check passed", shown)

    result = check(TrimFixture, sigs; project = Fixture.DIR, allow = [r"\.unstable\("])
    @test passed(result)

    stable_sigs = filter(sig -> !occursin("unstable", string(sig)), sigs)
    result = check(TrimFixture, stable_sigs; project = Fixture.DIR)
    @test result.compiled
    @test passed(result)
    @test isempty(result.errors) && isempty(result.allowed)

    workdir = mktempdir()
    result = record_and_check(
        TrimFixture;
        allow = ["TrimFixture.unstable(::Int64)"],
        workdir,
        test_project = Fixture.DIR,
        test_file = joinpath(Fixture.DIR, "test", "runtests.jl"),
    )
    @test passed(result)
    @test readlines(joinpath(workdir, "signatures.txt")) ==
          TrimTrace._signature_string.(result.signatures)
    @test isfile(joinpath(workdir, "entry.jl"))
    @test occursin("Signatures checked: 6", sprint(show, MIME"text/plain"(), result))
end
