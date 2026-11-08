"""
    uncovered(pkg::Module, sigs; exclude = Symbol[]) -> Vector{Symbol}

Return the public functions and concrete types of `pkg` that no signature in `sigs` calls.

Other names (abstract types, constants, modules, macros) are not reported.

# Arguments
- `pkg::Module`: the package whose public names are checked.
- `sigs`: the signatures as `Tuple{...}` expressions.

# Keywords
- `exclude = Symbol[]`: names never reported.

# Returns
The uncovered names, sorted.

# Examples
```jldoctest
julia> using TrimFixture  # the demo package in test/fixtures

julia> sigs = [:(Tuple{typeof(TrimFixture.stable), TrimFixture.Box})];

julia> uncovered(TrimFixture, sigs; exclude = [:Scaler])
4-element Vector{Symbol}:
 :Box
 :scaled
 :uncalled
 :unstable
```
"""
function uncovered(pkg::Module, sigs; exclude = Symbol[])
    covered = Set{Symbol}(_signature_callee(sig) for sig in sigs)
    missing_names = Symbol[]
    for name in names(pkg)
        (name === nameof(pkg) || name in exclude || name in covered) && continue
        startswith(string(name), '@') && continue
        isdefined(pkg, name) || continue
        obj = getfield(pkg, name)
        obj isa Function || (obj isa Type && !isabstracttype(obj)) || continue
        push!(missing_names, name)
    end
    return sort!(missing_names)
end

# The unqualified callee name of a `Tuple{...}` signature expression.
function _signature_callee(sig::Expr)
    _, callee, _ = _split_signature(sig)
    target = _strip_params(_is_object_callee(callee) ? callee : callee.args[end])
    return Meta.isexpr(target, :.) ? target.args[2].value : target
end

# `M.T{P}` and `M.T{P} where P` become `M.T`.
function _strip_params(ex)
    while Meta.isexpr(ex, :where) || Meta.isexpr(ex, :curly)
        ex = ex.args[1]
    end
    return ex
end

# Splits a signature into whether it is a keyword call, the callee parameter (`typeof(f)`,
# `Type{T}`, or the type of a called object) and the argument types, which start with the
# keyword `NamedTuple` for a keyword call.
function _split_signature(sig::Expr)
    params = sig.args[2:end]
    is_kwcall = params[1] == :(typeof(Core.kwcall))
    callee = is_kwcall ? params[3] : params[1]
    argtypes = is_kwcall ? [params[2]; params[4:end]] : params[2:end]
    return is_kwcall, callee, argtypes
end

_is_object_callee(callee) =
    !(Meta.isexpr(callee, :call) && callee.args[1] === :typeof) &&
    !(Meta.isexpr(callee, :curly) && callee.args[1] === :Type)
