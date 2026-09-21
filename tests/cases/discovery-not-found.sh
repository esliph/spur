# This case writes no Spurfile. Its ancestors are the harness directory,
# the temporary directory and /, none of which has one either.
run
assert_status 66
assert_stderr_has 'spur: no Spurfile found in'
assert_stderr_has 'or any parent directory'
