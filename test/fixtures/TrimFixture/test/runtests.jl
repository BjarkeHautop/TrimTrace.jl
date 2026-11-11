using TrimFixture

b = Box(1)
stable(b)
scaled(3; factor = 4)
TrimFixture._internal(5)

# Calls from a test helper and from a loop are compiled into their caller unless `record`
# interprets the test code, so these check that it does.
apply_scaler() = Scaler(2)(3)
apply_scaler()
for i in 1:2
    unstable(i)
end
