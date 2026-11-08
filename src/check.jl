"""
    TrimError

One error or warning reported by the trim verifier.

  - `kind`: `:error` or `:warning`.
  - `message`: the verifier's description, including the unresolved statement.
  - `entry`: the signature the problem was reached from, as the report prints it, such
    as `MyPkg.f(::Int64; k::Symbol)`. Without a stack trace it is the callee of the
    unresolved statement.
  - `value_dependent`: `true` when the unresolved statement involves a value used as a type
    (`::DataType`, `Val(x)`, `Type{T} where T`). Such calls usually resolve when the
    argument is a compile-time constant, which a recorded signature cannot express. In a
    [`check`](@ref) result it is also required that the signature passes such a value
    (a `DataType`, `Symbol`, `Type{T}`, ...), since otherwise the value comes from inside
    the package and every caller hits the error.
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
  - `signatures`: the signatures that were checked.
  - `log`: the path of the full juliac output.

Use [`passed`](@ref) to decide the outcome.
"""
struct TrimCheckResult
    compiled::Bool
    errors::Vector{TrimError}
    allowed::Vector{TrimError}
    signatures::Vector{Expr}
    log::String
end

"""
    passed(result::TrimCheckResult) -> Bool

Decide whether a [`check`](@ref) succeeded.

# Arguments
- `result::TrimCheckResult`: the outcome of [`check`](@ref).

# Returns
`true` when every verifier report is allowed and juliac either compiled the entry file or
failed only because of allowed reports.

# Examples
```jldoctest
julia> result = TrimTrace.TrimCheckResult(
           true, TrimTrace.TrimError[], TrimTrace.TrimError[], Expr[], "juliac.log");

julia> passed(result)
true
```
"""
passed(result::TrimCheckResult) =
    isempty(result.errors) && (result.compiled || !isempty(result.allowed))

"""
    check(pkg::Module, sigs; allow = [], project = nothing, workdir = mktempdir(),
          julia_args = String[]) -> TrimCheckResult

Compile the signatures `sigs` with `juliac --trim=safe` and parse the verifier output.

# Arguments
- `pkg::Module`: the package whose signatures are checked.
- `sigs`: the signatures as `Tuple{...}` expressions, as returned by [`record`](@ref).

# Keywords
- `allow = []`: known failures. Each entry is a `String` equal to a signature as the
  report prints it (for example `"MyPkg.f(::Int64; k::Symbol)"`) or a `Regex` matched
  against it. It can also be the path of a file with one entry per line (`#` starts a
  comment), where a line written as `r"..."` is a `Regex`, as in
  `r"^MyPkg\\.g\\(.*kind::DataType"`.
- `project = nothing`: the project juliac compiles in. With `nothing`, a project holding
  only `pkg` and the packages the signatures reference is generated in `workdir`, which
  keeps juliac from instantiating unrelated test dependencies.
- `workdir = mktempdir()`: the directory for the entry file, the generated project,
  `juliac.log` and `signatures.txt` (the checked signatures as the report prints them).
  It is created if missing.
- `julia_args = String[]`: arguments passed to the Julia process that compiles the image.

# Returns
A [`TrimCheckResult`](@ref TrimTrace.TrimCheckResult); use [`passed`](@ref) to decide
the outcome.

# Throws
- `ArgumentError`: `sigs` is empty, since an empty entry file compiles and would pass a
  check that tested nothing.

# Examples
```jldoctest; filter = [r"listed in .*", r"Full juliac output: .*"]
julia> using TrimFixture  # the demo package in test/fixtures

julia> sigs = record(TrimFixture; project = pkgdir(TrimFixture));

julia> check(TrimFixture, sigs; project = pkgdir(TrimFixture))
TrimTrace check failed: 1 errors (0 value-dependent), 0 warnings, 0 allowed
  1 x TrimFixture.unstable(::Int64)
Signatures checked: 6 (listed in /tmp/jl_JzYP0W/signatures.txt)
Full juliac output: /tmp/jl_JzYP0W/juliac.log

julia> allow = ["TrimFixture.unstable(::Int64)"];

julia> passed(check(TrimFixture, sigs; allow, project = pkgdir(TrimFixture)))
true
```
"""
function check(
    pkg::Module,
    sigs;
    allow = Union{String,Regex}[],
    project = nothing,
    workdir = mktempdir(),
    julia_args = String[],
)
    # An empty entry file compiles, which would pass a check that tested nothing.
    isempty(sigs) && throw(ArgumentError("no signatures to check"))
    allow = allow isa AbstractString ? _read_allowlist(allow) : collect(allow)
    mkpath(workdir)
    write(joinpath(workdir, "signatures.txt"), join(_signature_string.(sigs) .* "\n"))
    entry = _entry_file(joinpath(workdir, "entry.jl"), pkg, sigs)
    project = project === nothing ? _write_project(workdir, pkg, sigs) : abspath(project)
    log = joinpath(workdir, "juliac.log")
    # Only the compile step is needed: the trim verifier runs while compiling the image.
    image = JuliaC.ImageRecipe(;
        output_type = "--output-o",
        file = entry,
        project,
        trim_mode = "safe",
        julia_args = ["--experimental"; julia_args],
        img_path = joinpath(workdir, "entry.o.a"),
    )
    compiled = open(log, "w") do io
        redirect_stdio(; stdout = io, stderr = io) do
            try
                JuliaC.compile_products(image)
                true
            catch err
                err isa ErrorException || rethrow()
                false
            end
        end
    end
    reports = [_relabel(err, sigs) for err in _parse_juliac_log(log)]
    is_allowed(err) = any(pattern -> _matches(pattern, err.entry), allow)
    return TrimCheckResult(
        compiled,
        filter(!is_allowed, reports),
        filter(is_allowed, reports),
        collect(Expr, sigs),
        log,
    )
end

# The stripped lines of `path`, without blank lines and `#` comments.
function _read_lines(path::AbstractString)
    lines = String[]
    for line in eachline(path)
        stripped = strip(line)
        (isempty(stripped) || startswith(stripped, '#')) && continue
        push!(lines, stripped)
    end
    return lines
end

# A line written as `r"..."` is a `Regex`; any other line is an exact signature.
function _read_allowlist(path::AbstractString)
    return Union{String,Regex}[
        length(line) >= 3 && startswith(line, "r\"") && endswith(line, '"') ?
        Regex(line[3:(end-1)]) : String(line) for line in _read_lines(path)
    ]
end

_matches(pattern::AbstractString, entry) = pattern == entry
_matches(pattern::Regex, entry) = occursin(pattern, entry)

# Reports reached through the generated `entry_<i>` wrapper are labelled with signature `i`.
# A value-dependent report stays tagged only when the signature passes a value a caller
# could write as a constant; otherwise every caller of that signature hits it.
function _relabel(err::TrimError, sigs)
    m = match(r"^entry_(\d+)\(", err.entry)
    m === nothing && return err
    sig = sigs[parse(Int, m[1])]
    value_dependent = err.value_dependent && _passes_values(sig)
    return TrimError(err.kind, err.message, _signature_string(sig), value_dependent)
end

# Types of the values a call is usually written with as constants (`Float32`, `:name`).
const VALUE_TYPES = (:DataType, :UnionAll, :Union, :Symbol)

function _passes_values(sig::Expr)
    is_kwcall, _, argtypes = _split_signature(sig)
    types = is_kwcall ? [last.(_kwarg_types(argtypes[1])); argtypes[2:end]] : argtypes
    return any(types) do T
        T = _normalize_type(T)
        T in VALUE_TYPES || Meta.isexpr(T, :curly) && T.args[1] === :Type
    end
end

# The trace writes the type `DataType` as `typeof(DataType)`, and likewise for the other
# kinds of type.
function _normalize_type(T)
    Meta.isexpr(T, :call, 2) &&
        T.args[1] === :typeof &&
        T.args[2] in VALUE_TYPES &&
        return T.args[2]
    return T
end

# The `key => type` pairs of a keyword `NamedTuple{(:k,), Tuple{K}}`.
function _kwarg_types(nt)
    Meta.isexpr(nt, :curly) && length(nt.args) == 3 || return Pair{Any,Any}[]
    keys = [k isa QuoteNode ? k.value : k for k in nt.args[2].args]
    types_ex = nt.args[3]
    # The trace writes a homogeneous `Tuple{T, T, T}` as `NTuple{3, T}`.
    types = if types_ex.args[1] === :NTuple
        fill(types_ex.args[3], types_ex.args[2])
    else
        types_ex.args[2:end]
    end
    return Pair{Any,Any}[k => T for (k, T) in zip(keys, types)]
end

# Renders `Tuple{typeof(Core.kwcall), NamedTuple{(:k,), Tuple{K}}, typeof(f), A}` as
# `f(::A; k::K)`, a constructor call as `T(::A)` and a call to an object as `(::T)(::A)`.
function _signature_string(sig::Expr)
    is_kwcall, callee_ex, argtypes = _split_signature(sig)
    callee = if _is_object_callee(callee_ex)
        "(::$callee_ex)"
    elseif Meta.isexpr(callee_ex.args[end], :where)
        # `Type{(M.T{P, Q} where Q) where P}` is the constructor `M.T`.
        _strip_params(callee_ex.args[end])
    else
        callee_ex.args[end]
    end
    positional = is_kwcall ? argtypes[2:end] : argtypes
    args = join(("::$(_normalize_type(T))" for T in positional), ", ")
    kwargs = ""
    if is_kwcall
        pairs = _kwarg_types(argtypes[1])
        kwargs = "; " * join(("$k::$(_normalize_type(T))" for (k, T) in pairs), ", ")
    end
    return "$callee($args$kwargs)"
end

# Writes a juliac entry file that imports `pkg` and every package `sigs` reference, with
# one wrapper `entry_<i>` per signature that makes the call with concretely typed arguments
# and is marked with `Base.Experimental.entrypoint`. Marking the signature itself would let
# the compiler widen calls to vararg methods to the generic `Vararg` specialization, which
# an ordinary call site with a fixed number of arguments does not use.
function _entry_file(path::AbstractString, pkg::Module, sigs)
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
    is_kwcall, callee_ex, argtypes = _split_signature(sig)
    is_object = _is_object_callee(callee_ex)
    # A called object is passed in as the argument after the keyword `NamedTuple`.
    is_object && insert!(argtypes, is_kwcall + 1, callee_ex)
    args = [Symbol(:a, j) for j in eachindex(argtypes)]
    typed_args = [:($a::$T) for (a, T) in zip(args, argtypes)]
    # Both `typeof(f)` and `Type{T}` hold the callee as their last argument.
    callee = is_object ? args[is_kwcall+1] : callee_ex.args[end]
    rest = args[(is_kwcall+is_object+1):end]
    call = if is_kwcall
        :(Core.kwcall($(args[1]), $callee, $(rest...)))
    else
        :($callee($(rest...)))
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
            # A signature can name a dependency of `pkg` that the active environment lacks,
            # or a test dependency that `record` loaded from the test environment.
            pkgid = @something(
                Base.identify_package(String(root)),
                Base.identify_package(Base.PkgId(pkg), String(root)),
                _loaded_pkgid(root),
                Some(nothing),
            )
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

function _loaded_pkgid(root::Symbol)
    for pkgid in keys(Base.loaded_modules)
        pkgid.name == String(root) && pkgid.uuid !== nothing && return pkgid
    end
    return nothing
end

const REPORT_HEADER = r"^(Error|Warning) #\d+: "

# One `TrimError` per verifier report in the juliac log, in log order. Its `entry` is the
# generated `entry_<i>` wrapper frame, which `_relabel` maps back to a signature.
function _parse_juliac_log(path::AbstractString)
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
    frames = [replace(frame, r"^\[\d+\] " => "") for frame in frames]
    # The innermost `entry_<i>` frame is the generated wrapper, which names the signature.
    wrapper_idx = findlast(frame -> occursin(r"^entry_\d+\(", frame), frames)
    entry = if wrapper_idx !== nothing
        frames[wrapper_idx]
    elseif isempty(frames)
        _statement_callee(message)
    else
        last(frames)
    end
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
    # juliac failed before the verifier reported anything, so show why.
    if !result.compiled && isempty(result.errors) && isempty(result.allowed)
        println(io, "juliac failed without verifier reports; end of its output:")
        for line in last(readlines(result.log), 30)
            println(io, "  ", line)
        end
    end
    sigs_file = joinpath(dirname(result.log), "signatures.txt")
    println(io, "Signatures checked: $(length(result.signatures)) (listed in $sigs_file)")
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
