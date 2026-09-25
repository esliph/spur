# SPUR_TEST_JOBS must be a positive integer; anything else is a usage error
# before any case runs. Empty means unset, and more workers than cases are
# capped at the number of cases.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf ':\n' >fake/tests/cases/a-one.sh

# 07 is refused too: $((...)) would read it as octal.
for jobs in 0 abc -1 07 '4 2'; do
  capture env SPUR_TEST_JOBS="$jobs" "$shell_under_test" fake/tests/run.sh
  assert_status 64
  assert_stderr_has "SPUR_TEST_JOBS must be a positive integer, got: $jobs"
  assert_stdout_lacks 'passed'
done

capture env SPUR_TEST_JOBS= "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stdout_has '1 passed, 0 failed'

capture env SPUR_TEST_JOBS=99 "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stdout_has "1 passed, 0 failed (shell: $shell_under_test, jobs: 1)"
