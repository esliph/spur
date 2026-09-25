# SPUR_TEST_AWK picks the awk the runner runs with: the harness puts a
# wrapper named awk first on PATH, so the runner and every spur it starts use
# that command, extra words included. The summary names it. A command that
# cannot be found is a usage error before any case runs.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
cat >fake/tests/cases/a-list.sh <<'EOF'
spurfile <<'SPUR'
greet: ## say hello
  echo hello
SPUR
run --list
assert_status 0
assert_stdout_has 'say hello'
EOF

# The fake awk logs its first argument, drops it, and hands the rest to the
# real awk, so the case both sees it was used and sees the extra word arrive.
real_awk=$(command -v awk) || fail "no awk on PATH"
mkdir bin
cat >bin/logawk <<EOF
#!/bin/sh
printf '%s\n' "\$1" >>'$PWD/awk.log'
shift
exec '$real_awk' "\$@"
EOF
chmod +x bin/logawk

capture env SPUR_TEST_AWK="$PWD/bin/logawk --tag" "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stdout_has "1 passed, 0 failed (shell: $shell_under_test, jobs: 1, awk: $PWD/bin/logawk --tag)"
[ -f awk.log ] || fail "the runner did not use SPUR_TEST_AWK"
load_file awk.log
case $loaded in
  --tag*) ;;
  *) fail "the extra word did not reach the awk: $loaded" ;;
esac

capture env SPUR_TEST_AWK=no-such-awk-here "$shell_under_test" fake/tests/run.sh
assert_status 64
assert_stderr_has 'SPUR_TEST_AWK: cannot find no-such-awk-here'
assert_stdout_lacks 'passed'
