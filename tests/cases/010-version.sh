run -V
assert_status 0
assert_stdout_matches '^spur [0-9]+\.[0-9]+\.[0-9]+$'

run --version
assert_status 0
assert_stdout_matches '^spur [0-9]+\.[0-9]+\.[0-9]+$'
