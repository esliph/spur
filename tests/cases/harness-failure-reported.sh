# A failing case is reported as FAIL with its output indented under it, the
# others as ok, and the harness exits 1.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf ':\n' >fake/tests/cases/a-pass.sh
printf 'echo first line\necho second line\nexit 3\n' >fake/tests/cases/b-fail.sh
printf ':\n' >fake/tests/cases/c-pass.sh

capture env SPUR_TEST_JOBS=2 "$shell_under_test" fake/tests/run.sh
assert_status 1
assert_stdout_is <<EOF
ok   a-pass
FAIL b-fail
     first line
     second line
ok   c-pass

2 passed, 1 failed (shell: $shell_under_test, jobs: 2)
EOF
