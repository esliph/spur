run -h
assert_status 0
assert_stdout_has 'Usage:'
assert_stdout_has 'spur [runner flags] <task> [task arguments...]'

run --help
assert_status 0
assert_stdout_has 'Usage:'
