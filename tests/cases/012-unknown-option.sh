run -z
assert_status 64
assert_stderr_has 'spur: unknown option: -z'

# Short flags cannot be grouped: -xn is not -x -n.
run -xn build
assert_status 64
assert_stderr_has 'spur: unknown option: -xn'
