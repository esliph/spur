# A scenario whose command fails, or that never measures, fails the benchmark
# harness (exit 1) while the others still print their numbers, and the work
# directory is removed. Without a sub-second clock nothing runs (exit 69).
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
cat >fake/tests/bench/good.sh <<'EOF'
printf 'hello:\n  echo hello\n' >Spurfile
measure hello
EOF
cat >fake/tests/bench/bad.sh <<'EOF'
printf 'hello:\n  echo hello\n' >Spurfile
measure no-such-task
EOF
cat >fake/tests/bench/lazy.sh <<'EOF'
printf 'hello:\n  echo hello\n' >Spurfile
EOF
mkdir tmp

capture env SPUR_BENCH_ITERATIONS=2 SPUR_TEST_TMPDIR="$PWD/tmp" \
  "$shell_under_test" fake/tests/bench/run.sh
case $stderr in
  *'no sub-second clock'*)
    assert_status 69
    ;;
  *)
    assert_status 1
    assert_stdout_has 'FAIL bad'
    assert_stdout_has 'measure no-such-task: exited 67'
    assert_stdout_has 'spur: unknown task: no-such-task'
    assert_stdout_has 'FAIL lazy'
    assert_stdout_has 'the scenario never called measure'
    assert_stdout_matches '^good +2 runs   min +[0-9]+ ms   mean +[0-9]+ ms   max +[0-9]+ ms$'
    assert_stdout_has "shell: $shell_under_test, iterations: 2"
    ;;
esac
set -- tmp/*
if [ -e "$1" ]; then fail "work directory left behind: $1"; fi
