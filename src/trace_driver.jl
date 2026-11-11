# `record` runs this script in the child process, as
# `julia --trace-dispatch=<trace> trace_driver.jl <test file>`. It is not part of the
# TrimTrace module.

# Compile the test code without type inference. With inference, the compiler calls a
# function directly when it knows the argument types, as in a loop, a helper function or a
# closure passed to `map`, and `--trace-dispatch` only logs calls that go through dynamic
# dispatch. Without it, every call is dispatched at run time. This applies to `Main` and
# modules created in it; packages are loaded as separate modules and are compiled as usual.
Base.Experimental.@compiler_options infer = false

# Run the test file inside a test set. Outside one, a failing `@test` throws and stops the
# file, and the calls after it are never made.
let Test = Base.require(Main, :Test), test_file = popfirst!(ARGS)
    Base.ScopedValues.with(
        Test.CURRENT_TESTSET => Test.DefaultTestSet("TrimTrace"),
        Test.TESTSET_DEPTH => 1,
    ) do
        include(test_file)
    end
end
