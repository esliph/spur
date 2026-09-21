run -f
assert_status 64
assert_stderr_has 'spur: option -f requires an argument'

run -C
assert_status 64
assert_stderr_has 'spur: option -C requires an argument'
