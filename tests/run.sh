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
# Environment:
#   SPUR_TEST_SHELL     shell used to run the runner under test (default: sh)
#   SPUR_TEST_TMPDIR    where the per-case directories go (default: /tmp)

root=$(cd "$(dirname "$0")/.." && pwd)
runner=$root/spur
shell_under_test=${SPUR_TEST_SHELL:-sh}
filter=${1:-}
workdir=${SPUR_TEST_TMPDIR:-/tmp}/spur-tests.$$
passed=0
failed=0

# The runner exports its own state to child processes. When the suite is
# started through spur itself (./spur test), that state would leak into every
# case, so start from a clean slate.
unset SPUR_BIN SPUR_ROOT SPUR_INVOCATION_DIR SPUR_TASK SPUR_STACK

# shellcheck disable=SC2329  # invoked through the EXIT and INT traps
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT

mkdir -p "$workdir" || {
  printf 'cannot create %s\n' "$workdir" >&2
  exit 70
}

exact=
if [ -n "$filter" ] && [ -f "$root/tests/cases/$filter.sh" ]; then
  exact=1
fi

for case_file in "$root"/tests/cases/*.sh; do
  name=$(basename "$case_file" .sh)
  if [ -n "$exact" ]; then
    [ "$name" = "$filter" ] || continue
  else
    case $name in
      *"$filter"*) ;;
      *) continue ;;
    esac
  fi
  casedir=$workdir/$name
  mkdir -p "$casedir"
  if (
    cd "$casedir" || exit 1
    . "$root/tests/lib.sh"
    # shellcheck source=/dev/null
    . "$case_file"
  ) >"$workdir/$name.log" 2>&1; then
    passed=$((passed + 1))
    printf 'ok   %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$name"
    sed 's/^/     /' "$workdir/$name.log"
  fi
done

if [ $((passed + failed)) -eq 0 ]; then
  printf 'no test matches: %s\n' "$filter" >&2
  exit 64
fi

printf '\n%s passed, %s failed (shell: %s)\n' "$passed" "$failed" "$shell_under_test"
if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
