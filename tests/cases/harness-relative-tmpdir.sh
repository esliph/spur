# A relative SPUR_TEST_TMPDIR names a directory from where the harness was
# started, although every case and scenario runs from its own directory: the
# awk wrapper still comes first on PATH for the cases, and the benchmark
# harness still finds its result files.
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
EOF
cat >fake/tests/bench/hello.sh <<'EOF'
printf 'hello:\n  echo hello\n' >Spurfile
measure hello
EOF

real_awk=$(command -v awk) || fail "no awk on PATH"
mkdir bin tmp
cat >bin/logawk <<EOF
#!/bin/sh
printf 'used\n' >>'$PWD/awk.log'
exec '$real_awk' "\$@"
EOF
chmod +x bin/logawk

capture env SPUR_TEST_TMPDIR=tmp SPUR_TEST_AWK="$PWD/bin/logawk" \
  "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stdout_has '1 passed, 0 failed'
[ -f awk.log ] || fail "the runner did not use SPUR_TEST_AWK"

capture env SPUR_BENCH_ITERATIONS=1 SPUR_TEST_TMPDIR=tmp \
  "$shell_under_test" fake/tests/bench/run.sh
case $stderr in
  *'no sub-second clock'*) assert_status 69 ;;
  *)
    assert_status 0
    assert_stdout_matches '^hello +1 runs '
    ;;
esac
set -- tmp/*
if [ -e "$1" ]; then fail "work directory left behind: $1"; fi
