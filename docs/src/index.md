```@meta
CurrentModule = TrimTrace
```

# TrimTrace

Records the concrete call signatures a package's test suite makes into its public API and
checks that they compile under `juliac --trim=safe`. See the
[README](https://github.com/BjarkeHautop/TrimTrace.jl) for the workflow and limitations.
