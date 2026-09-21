run -C no-such-dir
assert_status 64
assert_stderr_has 'spur: cannot change directory: no-such-dir'
