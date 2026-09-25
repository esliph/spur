# The benchmark harness selects scenarios like the behavior harness selects
# cases, and selecting nothing is a usage error. Its own run.sh is not a
# scenario, not even by its exact name.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf 'measure --version\n' >fake/tests/bench/only.sh

capture "$shell_under_test" fake/tests/bench/run.sh nothing
assert_status 64
assert_stderr_has 'no benchmark matches: nothing'
assert_stdout_lacks 'only'

capture "$shell_under_test" fake/tests/bench/run.sh run
assert_status 64
assert_stderr_has 'no benchmark matches: run'
