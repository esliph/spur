# SPUR_BENCH_ITERATIONS must be a positive integer; anything else is a usage
# error before any scenario runs.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf 'measure --version\n' >fake/tests/bench/only.sh

for n in 0 abc -1 07; do
  capture env SPUR_BENCH_ITERATIONS="$n" "$shell_under_test" fake/tests/bench/run.sh
  assert_status 64
  assert_stderr_has "SPUR_BENCH_ITERATIONS must be a positive integer, got: $n"
  assert_stdout_lacks 'only'
done
