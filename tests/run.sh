#!/bin/sh
# Behavior tests for spur.
#
# Usage:
#   sh tests/run.sh [name]
#
# With a name, the case of exactly that name runs alone; when there is none,
# the name is a substring filter over the case names. Selecting nothing is a
# usage error (exit 64).
#
# The selected cases run in parallel workers, each case in a subshell in its
# own directory, with stdin closed. The report comes once every case has
# finished, in alphabetical order, so it reads the same with any number of
# workers.
#
# Environment:
#   SPUR_TEST_SHELL     shell used to run the runner under test (default: sh)
#   SPUR_TEST_TMPDIR    where the per-case directories go (default: /tmp)
#   SPUR_TEST_JOBS      number of workers (default: the number of CPUs);
#                       1 runs the cases one at a time
# shellcheck disable=SC2154  # $names and $count come from tests/common.sh

case $0 in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
root=$(cd "$here/.." && pwd)
runner=$root/spur
shell_under_test=${SPUR_TEST_SHELL:-sh}
filter=${1:-}
workdir=${SPUR_TEST_TMPDIR:-/tmp}/spur-tests.$$

# shellcheck source=tests/common.sh
. "$root/tests/common.sh"

# SPUR_TEST_JOBS is a positive integer; empty means unset. Leading zeros are
# refused, because $((...)) reads 010 as octal.
if [ -n "${SPUR_TEST_JOBS:-}" ]; then
  workers=$SPUR_TEST_JOBS
  case $workers in
    *[!0-9]* | 0*)
      printf 'SPUR_TEST_JOBS must be a positive integer, got: %s\n' "$workers" >&2
      exit 64
      ;;
  esac
else
  workers=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
  case $workers in
    '' | *[!0-9]* | 0*) workers=1 ;;
  esac
fi

# The runner exports its own state to child processes. When the suite is
# started through spur itself (./spur test), that state would leak into every
# case, so start from a clean slate. The harness's own controls go too: a
# case that starts a harness gets the defaults unless it asks otherwise.
unset SPUR_BIN SPUR_ROOT SPUR_INVOCATION_DIR SPUR_TASK SPUR_STACK SPUR_TEST_JOBS

select_names "$root/tests/cases" "$filter"
if [ "$count" -eq 0 ]; then
  printf 'no test matches: %s\n' "$filter" >&2
  exit 64
fi
[ "$workers" -le "$count" ] || workers=$count

# shellcheck disable=SC2317,SC2329  # invoked through the EXIT trap
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

mkdir -p "$workdir" || {
  printf 'cannot create %s\n' "$workdir" >&2
  exit 70
}

# interrupt STATUS -- let each worker finish the case it is running and start
# no other, wait for them, then exit with STATUS; the EXIT trap removes the
# work directory. Workers are asynchronous lists, which ignore SIGINT in a
# non-interactive shell, so a Ctrl-C reaches only this process and the stop
# has to be passed on. A second Ctrl-C stops waiting.
# shellcheck disable=SC2317,SC2329  # invoked through the INT and TERM traps
interrupt() {
  trap 'exit 130' INT
  : >"$workdir/.stop"
  wait
  exit "$1"
}
trap 'interrupt 130' INT
trap 'interrupt 143' TERM

# run_case NAME -- run one case, leaving its output in NAME.log and its exit
# status in NAME.status, next to its directory.
run_case() {
  mkdir "$workdir/$1"
  (
    cd "$workdir/$1" || exit 1
    . "$root/tests/lib.sh"
    # shellcheck source=/dev/null
    . "$root/tests/cases/$1.sh"
  ) >"$workdir/$1.log" 2>&1 </dev/null
  rc=$?
  printf '%s\n' "$rc" >"$workdir/$1.status"
}

# run_worker K -- run, one after another, the selected cases whose position in
# the list is K modulo the number of workers. Neighbours share a group and
# cost about the same, so round-robin spreads each group over the workers.
run_worker() {
  i=0
  # Case names are file names: no spaces, no glob characters.
  # shellcheck disable=SC2086
  for name in $names; do
    [ ! -f "$workdir/.stop" ] || return 0
    if [ $((i % workers)) -eq "$1" ]; then
      run_case "$name"
    fi
    i=$((i + 1))
  done
}

k=0
while [ "$k" -lt "$workers" ]; do
  run_worker "$k" &
  k=$((k + 1))
done
wait

passed=0
failed=0
# Case names are file names: no spaces, no glob characters.
# shellcheck disable=SC2086
for name in $names; do
  rc=
  if [ -f "$workdir/$name.status" ]; then
    read -r rc <"$workdir/$name.status"
  fi
  if [ "$rc" = 0 ]; then
    passed=$((passed + 1))
    printf 'ok   %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$name"
    sed 's/^/     /' "$workdir/$name.log"
  fi
done

printf '\n%s passed, %s failed (shell: %s, jobs: %s)\n' \
  "$passed" "$failed" "$shell_under_test" "$workers"
if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
