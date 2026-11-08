# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TrimTrace.jl records the concrete call signatures a package's test suite makes into its
public API, and checks that they compile under `juliac --trim=safe` (via JuliaC.jl). Needs
Julia 1.13+. The README covers user-facing behaviour and known limitations
(value-dependent calls, missed calls, varargs).

## Commands

The root `Project.toml` is a workspace (`projects = ["test", "docs"]`), so test and docs
environments share the root manifest.

```bash
# Full test suite (TestItemRunner; includes the slow juliac integration test)
julia --project -e 'using Pkg; Pkg.test()'

# Only fast unit tests, or a single test item by name
julia --project=test -e 'using TestItemRunner; TestItemRunner.run_tests("."; filter = ti -> :unit in ti.tags)'
julia --project=test -e 'using TestItemRunner; TestItemRunner.run_tests("."; filter = ti -> ti.name == "parse_juliac_log")'

# Docs (Documenter)
julia --project=docs docs/make.jl

# Lint / format with prek (reads .pre-commit-config.yaml; CI runs the Lint workflow)
prek run --all-files
```

Formatting is JuliaFormatter with `indent = 4`, `margin = 92`. The hooks include
`no-commit-to-branch`, so commits on `main` are rejected by the hook; work on a branch.

## Architecture

The pipeline is record → check, run together by `record_and_check` (locally or in CI);
each stage is one file in `src/`, and `ci.jl` ties them together. Only the user-facing
functions are exported (`TrimError`/`TrimCheckResult` are `public`); everything else is
`_`-prefixed and documented with comments instead of docstrings.

- **`extract.jl`** parses `precompile(Tuple{...})` lines from trace files into `Expr`
  signatures. Each line is evaluated in a sandbox module that binds every loaded package
  by name but *not* `Main`, so types defined in test files fail to resolve and are dropped.
  It keeps only calls whose callee is a public name of the package (`typeof(f)`,
  `Type{T}` constructors, an object of a public type, or `Core.kwcall` keyword calls),
  drops abstract argument types and (unless `abstract_params`) abstract type parameters, and expands a trailing
  `Vararg{A}` to a single `A`. Signatures are kept as `Expr`, not types, throughout.
- **`record.jl`** runs the target package's test file in a child Julia process with both
  `--trace-compile` and `--trace-dispatch`, then feeds both traces to `_extract_signatures`.
  Packages with legacy `[extras]`/`[targets]` test deps get a generated, instantiated temp
  test project (package deps plus test extras). Child processes drop inherited
  `JULIA_LOAD_PATH`/`JULIA_PROJECT` so `record` works when called under `Pkg.test`.
- **`signatures.jl`** implements `uncovered` and the helpers that split a signature
  `Expr` into keyword flag, callee and argument types.
- **`check.jl`** does the compile and reporting:
  - `_entry_file` writes a `TrimTraceEntry` module with one wrapper `entry_<i>` per
    signature (concretely typed args that make the call), each marked with
    `Base.Experimental.entrypoint`. Wrappers are used instead of marking the signature
    directly so vararg methods are not widened to the generic `Vararg` specialization.
  - With `project = nothing`, `_write_project` generates a minimal project containing only
    the package and packages referenced in the signatures (dev'ed packages via
    `[sources]` path), avoiding test-only deps.
  - Only JuliaC's compile step runs (`--output-o`); output goes to `juliac.log`, which
    `_parse_juliac_log` splits into `TrimError`s. `_relabel` maps `entry_<i>(` back to
    signature `i`, rendered by `_signature_string` as `f(::A; k::K)` (or `(::T)(::A)` for
    a called object). A report keeps its `value_dependent` tag only if the signature passes
    a `DataType`/`Symbol`/`Type{T}`-like value. Allowlist matching is done on those
    rendered strings, so changing the rendering changes the allowlist format.
  - `check` also writes `signatures.txt` (the rendered signatures) into `workdir` and
    keeps the signatures in the result, so a run can be inspected afterwards.
- **`ci.jl`** has `record_and_check` (record then check) and `write_ci_workflow`, which
  writes a GitHub Actions job running it from an environment holding TrimTrace and the
  dev'ed package.
- `record` appends the test project to `LOAD_PATH` while extracting, and `_write_project`
  falls back to already-loaded packages, so signatures naming test-only packages (e.g. an
  extension's trigger) resolve whatever environment TrimTrace runs from.

## Tests

Tests are `@testitem`s in `test/test-trimtrace.jl`, tagged `:unit` or
`:integration, :slow`. The `Fixture` test module puts `test/fixtures/TrimFixture` on
`LOAD_PATH`; that fixture package has a type-stable function, a trim-unstable one, a
kwarg function, an internal name and an uncalled public name, and its own
`test/runtests.jl` is what `record` traces in the integration test. The integration test
actually invokes juliac and is slow.
