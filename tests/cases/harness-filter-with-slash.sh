# A filter is a case name or a piece of one, never a path: one with a slash
# selects nothing, so it cannot reach a file outside tests/cases.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf ':\n' >fake/tests/cases/a-one.sh

capture "$shell_under_test" fake/tests/run.sh ../lib
assert_status 64
assert_stderr_has 'no test matches: ../lib'
assert_stdout_lacks 'ok'

capture "$shell_under_test" fake/tests/run.sh a/b
assert_status 64
