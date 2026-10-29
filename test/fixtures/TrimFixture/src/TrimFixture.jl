# A package with one trim-safe and one trim-unsafe public function, for TrimTrace's tests.
module TrimFixture

export Box, Scaler, stable, unstable, scaled, uncalled

struct Box
    x::Int
end

stable(b::Box) = b.x + 1

const REGISTRY = Any[1, "one"]

# `REGISTRY[i]` is `Any`, so `string` is a dynamic call the trim verifier rejects.
unstable(i::Int) = string(REGISTRY[i])

scaled(x::Int; factor::Int = 2) = x * factor

struct Scaler
    factor::Int
end

(s::Scaler)(x::Int) = s.factor * x

uncalled(x::Int) = x

_internal(x::Int) = x

end
