#!/bin/sh
# Benchmarks for spur.
#
# Usage:
#   sh tests/bench/run.sh [name]
#
# Selects scenarios in tests/bench/ the way tests/run.sh selects cases: an
# exact name, otherwise a substring filter; selecting nothing exits 64.
# Scenarios run one at a time, never in parallel, so they do not disturb
# each other's numbers. The output is numbers only: no baseline, no
# comparison, no threshold.
#
# A scenario is a straight-line script, run in its own temporary directory
# with $runner and $shell_under_test set. It prepares what it needs, then
# calls measure once:
#
#   measure ARGS...   run the runner with ARGS, output discarded: one warm-up
#                     run, then SPUR_BENCH_ITERATIONS timed runs. A failing
#                     run fails the scenario, since timing a broken command
#                     means nothing.
#
# Each timed run includes one call to date, the clock, so every number
# carries the same small overhead.
#
# Environment:
#   SPUR_TEST_SHELL        shell used to run the runner (default: sh)
#   SPUR_TEST_TMPDIR       where the scenario directories go (default: /tmp)
#   SPUR_BENCH_ITERATIONS  timed runs per scenario (default: 10)
#
# Exit status: 0 every scenario ran, 1 one failed, 64 usage error, 69 no
# sub-second clock, 70 the work directory could not be created.
# shellcheck disable=SC2154  # $names, $count, $clock and $ms come from tests/common.sh

case $0 in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
root=$(cd "$here/../.." && pwd)
runner=$root/spur
shell_under_test=${SPUR_TEST_SHELL:-sh}
filter=${1:-}
workdir=${SPUR_TEST_TMPDIR:-/tmp}/spur-bench.$$

# shellcheck source=tests/common.sh
. "$root/tests/common.sh"

# A positive integer; leading zeros are refused, as for SPUR_TEST_JOBS.
iterations=${SPUR_BENCH_ITERATIONS:-10}
case $iterations in
  *[!0-9]* | 0*)
    printf 'SPUR_BENCH_ITERATIONS must be a positive integer, got: %s\n' "$iterations" >&2
    exit 64
    ;;
esac

unset SPUR_BIN SPUR_ROOT SPUR_INVOCATION_DIR SPUR_TASK SPUR_STACK

# This file sits among the scenarios but is not one.
select_names "$root/tests/bench" "$filter" run
if [ "$count" -eq 0 ]; then
  printf 'no benchmark matches: %s\n' "$filter" >&2
  exit 64
fi

detect_clock
if [ -z "$clock" ]; then
  printf 'no sub-second clock: date +%%s%%N does not print nanoseconds here\n' >&2
  exit 69
fi

# shellcheck disable=SC2317,SC2329  # invoked through the EXIT trap
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$workdir" || {
  printf 'cannot create %s\n' "$workdir" >&2
  exit 70
}

# measure_failed STATUS ARGS... -- end the scenario after a failing run,
# showing what the runner printed on stderr.
# shellcheck disable=SC2329  # called by measure, which the sourced scenarios call
measure_failed() {
  code=$1
  shift
  printf 'measure %s: exited %s\n' "$*" "$code"
  cat "$bench_errors"
  exit 1
}

# measure ARGS... -- time the runner with ARGS: one warm-up run, then
# $iterations timed runs. Leaves "RUNS MIN MEAN MAX" in the scenario's
# result file.
# shellcheck disable=SC2329  # called by the scenarios sourced below
measure() {
  if [ -f "$bench_result" ]; then
    printf 'measure called twice: one measurement per scenario\n'
    exit 1
  fi
  "$shell_under_test" "$runner" "$@" >/dev/null 2>"$bench_errors" ||
    measure_failed "$?" "$@"
  n=0
  min=
  max=0
  sum=0
  while [ "$n" -lt "$iterations" ]; do
    now_ms
    start=$ms
    "$shell_under_test" "$runner" "$@" >/dev/null 2>"$bench_errors" ||
      measure_failed "$?" "$@"
    now_ms
    t=$((ms - start))
    if [ -z "$min" ] || [ "$t" -lt "$min" ]; then min=$t; fi
    if [ "$t" -gt "$max" ]; then max=$t; fi
    sum=$((sum + t))
    n=$((n + 1))
  done
  printf '%s %s %s %s\n' "$n" "$min" "$((sum / n))" "$max" >"$bench_result"
}

width=0
# Scenario names are file names: no spaces, no glob characters.
# shellcheck disable=SC2086
for name in $names; do
  [ "${#name}" -le "$width" ] || width=${#name}
done

failed=0
# shellcheck disable=SC2086
for name in $names; do
  bench_result=$workdir/$name.result
  bench_errors=$workdir/$name.errors
  mkdir "$workdir/$name"
  if (
    cd "$workdir/$name" || exit 1
    # shellcheck source=/dev/null
    . "$root/tests/bench/$name.sh"
    if [ ! -f "$bench_result" ]; then
      printf 'the scenario never called measure\n'
      exit 1
    fi
  ) >"$workdir/$name.log" 2>&1 </dev/null; then
    read -r runs min mean max <"$bench_result"
    label=$name
    while [ "${#label}" -lt "$width" ]; do label="$label "; done
    printf '%s  %3s runs   min %5s ms   mean %5s ms   max %5s ms\n' \
      "$label" "$runs" "$min" "$mean" "$max"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$name"
    sed 's/^/     /' "$workdir/$name.log"
  fi
done

printf '\nshell: %s, iterations: %s\n' "$shell_under_test" "$iterations"
if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
