# With SPUR_TEST_TIMES=1 each report line ends with the case's duration and
# the five slowest are listed after the summary. Where date has no
# sub-second clock the harness says so on stderr and carries on without
# timings; both outcomes are accepted, as in trace-flag.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
cat >fake/tests/cases/a-one.sh <<'EOF'
# The harness's own controls do not reach the cases.
if [ -n "${SPUR_TEST_TIMES+set}" ]; then echo "SPUR_TEST_TIMES leaked"; exit 1; fi
if [ -n "${SPUR_TEST_JOBS+set}" ]; then echo "SPUR_TEST_JOBS leaked"; exit 1; fi
EOF
printf ':\n' >fake/tests/cases/b-two.sh

capture env SPUR_TEST_TIMES=1 SPUR_TEST_JOBS=2 "$shell_under_test" fake/tests/run.sh
assert_status 0
case $stderr in
  *'timings unavailable'*)
    assert_stdout_has 'ok   a-one'
    assert_stdout_lacks ' ms)'
    ;;
  *)
    assert_stdout_matches '^ok   a-one  \([0-9]+ ms\)$'
    assert_stdout_matches '^ok   b-two  \([0-9]+ ms\)$'
    assert_stdout_has "2 passed, 0 failed (shell: $shell_under_test, jobs: 2)"
    assert_stdout_has 'slowest:'
    assert_stdout_matches '^ +[0-9]+ ms  a-one$'
    assert_stdout_matches '^ +[0-9]+ ms  b-two$'
    ;;
esac
