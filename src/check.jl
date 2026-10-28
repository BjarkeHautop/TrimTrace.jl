"""
    TrimError

One error or warning reported by the trim verifier.

  - `kind`: `:error` or `:warning`.
  - `message`: the verifier's description, including the unresolved statement.
  - `entry`: the outermost stack frame, which is the entry point (recorded signature) the
    problem was reached from.
  - `value_dependent`: `true` when the unresolved statement involves a value used as a type
    (`::DataType`, `Val(x)`, `Type{T} where T`). Such calls usually resolve when the
    argument is a compile-time constant, which a recorded signature cannot express.
"""
struct TrimError
    kind::Symbol
    message::String
    entry::String
    value_dependent::Bool
end

"""
    TrimCheckResult

The outcome of [`check`](@ref).

  - `compiled`: `true` when juliac compiled the entry file.
  - `errors`: the verifier reports not covered by the allowlist.
  - `allowed`: the verifier reports covered by the allowlist.
  - `stale`: allowlist entries that matched no report, which can be removed.
  - `log`: the path of the full juliac output.

Use [`passed`](@ref) to decide the outcome.
"""
struct TrimCheckResult
    compiled::Bool
    errors::Vector{TrimError}
    allowed::Vector{TrimError}
    stale::Vector{Union{String,Regex}}
    log::String
end

"""
    passed(result::TrimCheckResult) -> Bool

`true` when every verifier report is allowed and juliac either compiled the entry file or
failed only because of allowed reports.
"""
passed(result::TrimCheckResult) =
    isempty(result.errors) && (result.compiled || !isempty(result.allowed))

"""
    check(pkg::Module, sigs; allow = [], project = nothing, workdir = mktempdir(),
          juliac_args = String[]) -> TrimCheckResult

Compile the signatures `sigs` (or the file written by [`write_signatures`](@ref), when
`sigs` is a path) with `juliac --trim=safe` and parse the verifier output.

`allow` lists known failures: each entry is a `String` equal to a signature as the report
prints it (for example `"MyPkg.f(::Int64; k::Symbol)"`) or a `Regex` matched against it.
It can also be the path of a file with one such string per line (`#` starts a comment).
Allowed signatures are still compiled, so entries that stop matching show up as `stale`.

With `project = nothing`, a project holding only `pkg` and the packages the signatures
reference is generated in `workdir`, which keeps juliac from instantiating unrelated test
dependencies. `juliac_args` are appended to the juliac command line.
"""
function check(
    pkg::Module,
    sigs;
    allow = Union{String,Regex}[],
    project = nothing,
    workdir = mktempdir(),
    juliac_args = String[],
)
    sigs = sigs isa AbstractString ? read_signatures(sigs) : sigs
    allow = allow isa AbstractString ? _read_lines(allow) : collect(allow)
    entry = entry_file(joinpath(workdir, "entry.jl"), pkg, sigs)
    project = project === nothing ? _write_project(workdir, pkg, sigs) : abspath(project)
    log = joinpath(workdir, "juliac.log")
    args = [
        "--output-o",
        joinpath(workdir, "entry.o"),
        "--project",
        project,
        "--trim=safe",
        "--experimental",
        juliac_args...,
        entry,
    ]
    compiled = open(log, "w") do io
        redirect_stdio(; stdout = io, stderr = io) do
            try
                JuliaC.main(args)
                true
            catch err
                err isa ErrorException || rethrow()
                false
            end
        end
    end
    reports = [_relabel(err, sigs) for err in parse_juliac_log(log)]
    is_allowed(err) = any(pattern -> _matches(pattern, err.entry), allow)
    stale = [p for p in allow if !any(err -> _matches(p, err.entry), reports)]
    return TrimCheckResult(
        compiled,
        filter(!is_allowed, reports),
        filter(is_allowed, reports),
        stale,
        log,
    )
end

_matches(pattern::AbstractString, entry) = pattern == entry
_matches(pattern::Regex, entry) = occursin(pattern, entry)

# Reports reached through the generated `entry_<i>` wrapper are labelled with signature `i`.
function _relabel(err::TrimError, sigs)
    m = match(r"^entry_(\d+)\(", err.entry)
    m === nothing && return err
    entry = _signature_string(sigs[parse(Int, m[1])])
    return TrimError(err.kind, err.message, entry, err.value_dependent)
end

# Renders `Tuple{typeof(Core.kwcall), NamedTuple{(:k,), Tuple{K}}, typeof(f), A}` as
# `f(::A; k::K)`.
function _signature_string(sig::Expr)
    params = sig.args[2:end]
    is_kwcall = params[1] == :(typeof(Core.kwcall))
    callee = (is_kwcall ? params[3] : params[1]).args[end]
    args = join(("::$T" for T in params[(is_kwcall ? 4 : 2):end]), ", ")
    kwargs = ""
    if is_kwcall && Meta.isexpr(params[2], :curly) && length(params[2].args) == 3
        keys = [k isa QuoteNode ? k.value : k for k in params[2].args[2].args]
        types = params[2].args[3].args[2:end]
        kwargs = "; " * join(("$k::$T" for (k, T) in zip(keys, types)), ", ")
    end
    return "$callee($args$kwargs)"
end

"""
    entry_file(path, pkg::Module, sigs) -> path

Write a juliac entry file to `path` that imports `pkg` and every package `sigs` reference.
Each signature gets a wrapper function with concretely typed arguments that makes the
call, and the wrapper is marked as a trim entry point with `Base.Experimental.entrypoint`.

Marking the signature itself would let the compiler widen calls to vararg methods to the
generic `Vararg` specialization, which an ordinary call site with a fixed number of
arguments does not use.
"""
function entry_file(path::AbstractString, pkg::Module, sigs)
    open(path, "w") do io
        println(io, "module TrimTraceEntry")
        println(io)
        for root in _import_roots(pkg, sigs)
            println(io, "import ", root)
        end
        for (i, sig) in enumerate(sigs)
            name = Symbol(:entry_, i)
            wrapper, argtypes = _entry_wrapper(name, sig)
            println(io)
            println(io, "# ", sig)
            println(io, wrapper)
            println(io, "Base.Experimental.entrypoint(", name, ", ", argtypes, ")")
        end
        println(io)
        println(io, "end")
    end
    return path
end

function _entry_wrapper(name, sig::Expr)
    params = sig.args[2:end]
    is_kwcall = params[1] == :(typeof(Core.kwcall))
    callee_ex = is_kwcall ? params[3] : params[1]
    # Both `typeof(f)` and `Type{T}` hold the callee as their last argument.
    callee = callee_ex.args[end]
    argtypes = is_kwcall ? [params[2]; params[4:end]] : params[2:end]
    args = [Symbol(:a, j) for j in eachindex(argtypes)]
    typed_args = [:($a::$T) for (a, T) in zip(args, argtypes)]
    call = if is_kwcall
        :(Core.kwcall($(args[1]), $callee, $(args[2:end]...)))
    else
        :($callee($(args...)))
    end
    wrapper = :(function $name($(typed_args...))
        return $call
    end)
    return Base.remove_linenums!(wrapper), Expr(:tuple, argtypes...)
end

function _import_roots(pkg, sigs)
    roots = Set{Symbol}([nameof(pkg)])
    foreach(sig -> _collect_roots!(roots, sig), sigs)
    setdiff!(roots, (:Core, :Base))
    return sort!(collect(roots))
end

# Collects the leftmost name of every qualified reference such as `Random.Xoshiro`.
function _collect_roots!(roots, ex)
    if Meta.isexpr(ex, :.)
        head = ex
        while Meta.isexpr(head, :.)
            head = head.args[1]
        end
        head isa Symbol && push!(roots, head)
    elseif ex isa Expr
        foreach(arg -> _collect_roots!(roots, arg), ex.args)
    end
    return roots
end

# A dev'ed package is referenced by path so juliac builds the working copy.
function _write_project(workdir, pkg, sigs)
    dir = joinpath(workdir, "project")
    mkpath(dir)
    open(joinpath(dir, "Project.toml"), "w") do io
        println(io, "[deps]")
        for root in _import_roots(pkg, sigs)
            pkgid = Base.identify_package(String(root))
            pkgid === nothing &&
                error("cannot find package `$root` in the active environment")
            println(io, root, " = \"", pkgid.uuid, "\"")
        end
        pkg_path = pkgdir(pkg)
        if pkg_path !== nothing && !occursin(joinpath(".julia", "packages"), pkg_path)
            println(io)
            println(io, "[sources]")
            println(io, nameof(pkg), " = {path = ", repr(pkg_path), "}")
        end
    end
    return dir
end

const REPORT_HEADER = r"^(Error|Warning) #\d+: "

"""
    parse_juliac_log(path) -> Vector{TrimError}

Parse the trim verifier reports out of a juliac log.
"""
function parse_juliac_log(path::AbstractString)
    lines = readlines(path)
    starts = findall(line -> occursin(REPORT_HEADER, line), lines)
    errors = TrimError[]
    for (i, start) in enumerate(starts)
        stop = i < length(starts) ? starts[i+1] - 1 : _report_end(lines, start)
        push!(errors, _parse_report(lines[start:stop]))
    end
    return errors
end

function _report_end(lines, start)
    stop = findnext(line -> startswith(line, "Trim verify finished"), lines, start)
    return stop === nothing ? length(lines) : stop - 1
end

function _parse_report(block)
    kind = startswith(block[1], "Error") ? :error : :warning
    trace_idx = findfirst(==("Stacktrace:"), block)
    message_lines = trace_idx === nothing ? block : block[1:(trace_idx-1)]
    message = strip(join(message_lines, '\n'))
    frames =
        trace_idx === nothing ? String[] :
        [
            strip(line) for
            line in block[(trace_idx+1):end] if occursin(r"^\s*\[\d+\] ", line)
        ]
    entry =
        isempty(frames) ? _statement_callee(message) :
        replace(last(frames), r"^\[\d+\] " => "")
    return TrimError(kind, message, entry, _is_value_dependent(message))
end

_statement_callee(message) =
    strip(replace(first(split(message, '\n')), REPORT_HEADER => ""))

_is_value_dependent(message) =
    occursin("::DataType", message) ||
    occursin("Val{_A}", message) ||
    occursin(r"::Type\{[^}]*\} where", message)

function Base.show(io::IO, ::MIME"text/plain", result::TrimCheckResult)
    nerr = count(e -> e.kind === :error, result.errors)
    nvalue = count(e -> e.kind === :error && e.value_dependent, result.errors)
    nwarn = length(result.errors) - nerr
    status = passed(result) ? "passed" : "failed"
    println(
        io,
        "TrimTrace check $status: $nerr errors ($nvalue value-dependent), $nwarn warnings, " *
        "$(length(result.allowed)) allowed",
    )
    _show_by_entry(io, result.errors)
    if !isempty(result.stale)
        println(io, "Allowlist entries matching no report (can be removed):")
        foreach(p -> println(io, "  ", p), result.stale)
    end
    print(io, "Full juliac output: ", result.log)
end

function _show_by_entry(io, errors)
    by_entry = Dict{String,Vector{TrimError}}()
    for err in errors
        push!(get!(by_entry, err.entry, TrimError[]), err)
    end
    for entry in sort!(collect(keys(by_entry)))
        errs = by_entry[entry]
        tag = all(e -> e.value_dependent, errs) ? " [value-dependent]" : ""
        println(io, "  ", length(errs), " x ", entry, tag)
    end
end
