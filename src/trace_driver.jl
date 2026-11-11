# `record` runs this script in the child process, as
# `julia --trace-dispatch=<trace> trace_driver.jl <test file>`. It is not part of the
# TrimTrace module.

# Interpret the test code instead of compiling it. Compiled code calls a function directly
# when the argument types are known, as in a loop or a helper function, and
# `--trace-dispatch` only logs calls that go through dynamic dispatch. Interpreted code
# dispatches every call. This applies to `Main` and modules created in it; packages are
# loaded as separate modules and stay compiled.
Base.Experimental.@compiler_options compile = min infer = false

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
