"""
    extract_signatures(pkg::Module, traces; exclude = Symbol[]) -> Vector{Expr}

Parse `--trace-compile` or `--trace-dispatch` output files (a path or a vector of paths)
and return the recorded signatures, as
`Tuple{...}` expressions, whose callee is a public name of `pkg`. That covers positional
calls `Tuple{typeof(f), A}`, keyword calls `Tuple{typeof(Core.kwcall), NamedTuple{...},
typeof(f), A}` and constructor calls `Tuple{Type{T}, A}`.

A signature is dropped when it cannot be evaluated outside the recording process (for
example types defined in the test files), has a non-concrete argument type, or calls a
name listed in `exclude`. A trailing `Vararg{A}` is replaced by a single `A`. The result is
sorted and deduplicated.
"""
extract_signatures(pkg::Module, trace::AbstractString; exclude = Symbol[]) =
    extract_signatures(pkg, [trace]; exclude)

function extract_signatures(
    pkg::Module,
    traces::AbstractVector{<:AbstractString};
    exclude = Symbol[],
)
    sandbox = _sandbox_module()
    public = Set(names(pkg))
    sigs = Set{Expr}()
    for line in Iterators.flatten(eachline.(traces))
        tuple_ex = _parse_trace_line(line)
        tuple_ex === nothing && continue
        _bind_roots!(sandbox, tuple_ex)
        sig = try
            Core.eval(sandbox, tuple_ex)
        catch
            continue
        end
        name = _callee_name(pkg, public, sig)
        name === nothing || name in exclude || push!(sigs, _expand_vararg(tuple_ex))
    end
    return sort!(collect(sigs); by = string)
end

# Every loaded package is bound by name so the fully qualified names in the trace resolve,
# while `Main` is left out so types defined by the test files fail to evaluate.
function _sandbox_module()
    sandbox = Module(:TrimTraceSandbox)
    for mod in values(Base.loaded_modules)
        name = nameof(mod)
        isdefined(sandbox, name) || Core.eval(sandbox, :(const $name = $mod))
    end
    return sandbox
end

# Loads packages the signature references that are not loaded yet, when the active
# environment provides them.
function _bind_roots!(sandbox, tuple_ex)
    for root in _collect_roots!(Set{Symbol}(), tuple_ex)
        isdefined(sandbox, root) && continue
        pkgid = Base.identify_package(String(root))
        pkgid === nothing && continue
        mod = try
            Base.require(pkgid)
        catch
            continue
        end
        Core.eval(sandbox, :(const $root = $mod))
    end
    return sandbox
end

function _parse_trace_line(line::AbstractString)
    startswith(line, "precompile(") || return nothing
    ex = Meta.parse(line; raise = false)
    Meta.isexpr(ex, :call, 2) && ex.args[1] === :precompile || return nothing
    tuple_ex = ex.args[2]
    Meta.isexpr(tuple_ex, :curly) && tuple_ex.args[1] === :Tuple || return nothing
    return tuple_ex
end

# Returns the public name `sig` calls, or `nothing` when the callee is not public in `pkg`
# or an argument type is not concrete.
function _callee_name(pkg, public, sig)
    sig isa DataType && sig <: Tuple || return nothing
    params = sig.parameters
    is_kwcall = !isempty(params) && params[1] === typeof(Core.kwcall)
    callee_idx = is_kwcall ? 3 : 1
    length(params) >= callee_idx || return nothing
    is_kwcall && !isconcretetype(params[2]) && return nothing
    all(_is_valid_arg, params[(callee_idx+1):end]) || return nothing

    ft = params[callee_idx]
    obj = if ft isa DataType && isdefined(ft, :instance) && ft.instance isa Function
        ft.instance
    elseif Base.isType(ft)
        Base.unwrap_unionall(ft.parameters[1]).name.wrapper
    else
        return nothing
    end
    name = nameof(obj)
    name in public && isdefined(pkg, name) && getfield(pkg, name) === obj || return nothing
    return name
end

# The trace holds the generic `Vararg` specialization, which a call with a fixed number of
# arguments never uses, so a trailing `Vararg{A}` becomes a single `A`.
function _expand_vararg(tuple_ex::Expr)
    last_ex = tuple_ex.args[end]
    Meta.isexpr(last_ex, :curly) && last_ex.args[1] === :Vararg || return tuple_ex
    return Expr(:curly, tuple_ex.args[1:(end-1)]..., last_ex.args[2])
end

function _is_valid_arg(T)
    T isa Core.TypeofVararg && return isdefined(T, :T) && _is_valid_arg(T.T)
    return isconcretetype(T) || Base.isType(T)
end
