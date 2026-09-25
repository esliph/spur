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
#   SPUR_TEST_TIMES     1 adds each case's duration and lists the five slowest
#   SPUR_TEST_AWK       awk the runner runs with, words split on spaces and
#                       no quoting: gawk --posix, mawk, busybox awk
#                       (default: the awk on PATH)
# shellcheck disable=SC2154  # $names, $count, $clock and $ms come from tests/common.sh

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

# SPUR_TEST_AWK: resolve its first word now, so a typo is a usage error
# before any case runs; the wrapper is written once the work directory
# exists.
awk_cmd=${SPUR_TEST_AWK:-}
awk_path=
if [ -n "$awk_cmd" ]; then
  # Split on spaces on purpose: the value is a command and its words.
  # shellcheck disable=SC2086
  set -- $awk_cmd
  awk_path=$(command -v "$1" 2>/dev/null) || awk_path=
  case $awk_path in
    /*) ;;
    */*) awk_path=$PWD/$awk_path ;;
    *)
      printf 'SPUR_TEST_AWK: cannot find %s\n' "$1" >&2
      exit 64
      ;;
  esac
  shift
  awk_args=$*
fi

timing=
if [ "${SPUR_TEST_TIMES:-}" = 1 ]; then
  detect_clock
  if [ -n "$clock" ]; then
    timing=1
  else
    printf 'timings unavailable: date +%%s%%N does not print nanoseconds here\n' >&2
  fi
fi

# The runner exports its own state to child processes. When the suite is
# started through spur itself (./spur test), that state would leak into every
# case, so start from a clean slate. The harness's own controls go too: a
# case that starts a harness gets the defaults unless it asks otherwise. The
# awk chosen by SPUR_TEST_AWK stays chosen there, through PATH.
unset SPUR_BIN SPUR_ROOT SPUR_INVOCATION_DIR SPUR_TASK SPUR_STACK \
  SPUR_TEST_JOBS SPUR_TEST_TIMES SPUR_TEST_AWK

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

# A script named awk, first on PATH, that execs the chosen awk by its
# absolute path. A symlink would not carry the extra words, and under MSYS
# (Git Bash) a copied binary no longer finds its DLLs.
if [ -n "$awk_path" ]; then
  mkdir "$workdir/.awk"
  printf '#!/bin/sh\nexec '\''%s'\'' %s "$@"\n' "$awk_path" "$awk_args" \
    >"$workdir/.awk/awk"
  chmod +x "$workdir/.awk/awk"
  PATH=$workdir/.awk:$PATH
  export PATH
fi

# interrupt STATUS -- let each worker finish the case it is running and start
# no other, wait for them, then exit with STATUS; the EXIT trap removes the
# work directory. Workers are asynchronous lists, which ignore SIGINT in a
# non-interactive shell, so a Ctrl-C reaches only this process and the stop
# has to be passed on. A second INT or TERM stops waiting: the workers are
# killed, since one left running would go on to the next case in a work
# directory that is about to be removed.
# shellcheck disable=SC2317,SC2329  # invoked through the INT and TERM traps
interrupt() {
  # shellcheck disable=SC2064  # $pids is meant to be expanded now
  trap "kill $pids 2>/dev/null; exit 130" INT TERM
  : >"$workdir/.stop"
  wait
  exit "$1"
}
trap 'interrupt 130' INT
trap 'interrupt 143' TERM

# run_case NAME -- run one case, leaving its output in NAME.log and, in
# NAME.status, its exit status followed by its duration in milliseconds when
# timing is on.
run_case() {
  mkdir "$workdir/$1"
  if [ -n "$timing" ]; then
    now_ms
    start=$ms
  fi
  (
    cd "$workdir/$1" || exit 1
    . "$root/tests/lib.sh"
    # shellcheck source=/dev/null
    . "$root/tests/cases/$1.sh"
  ) >"$workdir/$1.log" 2>&1 </dev/null
  rc=$?
  elapsed=
  if [ -n "$timing" ]; then
    now_ms
    elapsed=$((ms - start))
  fi
  printf '%s %s\n' "$rc" "$elapsed" >"$workdir/$1.status"
}

# run_worker K -- run, one after another, the selected cases whose position in
# the list is K modulo the number of workers. Neighbours share a group and
# cost about the same, so round-robin spreads each group over the workers.
run_worker() {
  i=0
  # Case names are file names: no spaces, no glob characters.
  # shellcheck disable=SC2086
  for name in $names; do
    [ -d "$workdir" ] && [ ! -f "$workdir/.stop" ] || return 0
    if [ $((i % workers)) -eq "$1" ]; then
      run_case "$name"
    fi
    i=$((i + 1))
  done
}

pids=
k=0
while [ "$k" -lt "$workers" ]; do
  run_worker "$k" &
  pids="$pids $!"
  k=$((k + 1))
done
wait

passed=0
failed=0
slowest=
# Case names are file names: no spaces, no glob characters.
# shellcheck disable=SC2086
for name in $names; do
  rc=
  elapsed=
  if [ -f "$workdir/$name.status" ]; then
    read -r rc elapsed <"$workdir/$name.status"
  fi
  suffix=${elapsed:+  ($elapsed ms)}
  if [ "$rc" = 0 ]; then
    passed=$((passed + 1))
    printf 'ok   %s%s\n' "$name" "$suffix"
  else
    failed=$((failed + 1))
    printf 'FAIL %s%s\n' "$name" "$suffix"
    sed 's/^/     /' "$workdir/$name.log"
  fi
  if [ -n "$elapsed" ]; then
    slowest="$slowest$elapsed $name
"
  fi
done

printf '\n%s passed, %s failed (shell: %s, jobs: %s%s)\n' \
  "$passed" "$failed" "$shell_under_test" "$workers" "${awk_cmd:+, awk: $awk_cmd}"
if [ -n "$timing" ]; then
  printf '\nslowest:\n'
  printf '%s' "$slowest" | sort -rn | sed 5q | while read -r t n; do
    printf '%8s ms  %s\n' "$t" "$n"
  done
fi
if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
