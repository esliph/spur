run -f missing.spur
assert_status 66
assert_stderr_has 'spur: missing.spur: no such file'
