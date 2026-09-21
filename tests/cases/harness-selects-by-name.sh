# The harness itself: a case is selected by its exact name, then by substring.
# Only cases that never start the harness again may be selected here.
# shellcheck disable=SC2154  # $root and $shell_under_test come from tests/run.sh
harness() {
  "$shell_under_test" "$root/tests/run.sh" "$@" >stdout 2>stderr
  status=$?
  return 0
}

# An exact name runs that case alone, even when other names contain it.
harness discovery-flag-f
assert_status 0
assert_stdout_has 'ok   discovery-flag-f'
assert_stdout_lacks 'discovery-flag-f-missing'
assert_stdout_has '1 passed, 0 failed'

# No exact match: the argument is a substring filter.
harness discovery-flag-f-
assert_status 0
assert_stdout_has 'ok   discovery-flag-f-missing'
assert_stdout_lacks 'ok   discovery-flag-f '

harness cli-version
assert_status 0
assert_stdout_has '1 passed, 0 failed'

# Nothing matches: a usage error, not a green "0 passed".
harness no-such-case
assert_status 64
assert_stdout_lacks 'passed'
assert_stderr_has 'no test matches: no-such-case'

# The prefixes group cases by theme: a prefix selects the whole group.
harness cli-
assert_status 0
assert_stdout_has '4 passed, 0 failed'
