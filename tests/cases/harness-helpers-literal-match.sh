# capture fills $stdout and $stderr, and the has/lacks assertions match them
# as fixed strings, the way grep -F did: characters that mean something in a
# shell pattern are matched as themselves. A last line with no trailing
# newline is kept.

capture printf 'a*c [x] ?\nlast line, no newline'
assert_status 0
assert_stdout_has 'a*c'
assert_stdout_has '[x] ?'
assert_stdout_has 'last line, no newline'
# As shell patterns these would match the output; as fixed strings they do not.
assert_stdout_lacks 'a?c'
assert_stdout_lacks '[a]'
assert_stderr_lacks 'a*c'

# A failing assertion fails the case: run each in a subshell and expect it
# to exit non-zero.
if (assert_stdout_has 'absent') >/dev/null; then
  fail "assert_stdout_has passed on absent text"
fi
if (assert_stdout_lacks 'a*c') >/dev/null; then
  fail "assert_stdout_lacks passed on present text"
fi

# A second capture replaces what the first one loaded.
capture sh -c 'printf "oops\n" >&2; exit 3'
assert_status 3
assert_stderr_has 'oops'
assert_stdout_lacks 'a*c'
