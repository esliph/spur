#!/bin/sh
# Behavior tests for spur.
#
# Usage:
#   sh tests/run.sh [name-filter]
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

cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT

mkdir -p "$workdir" || {
  printf 'cannot create %s\n' "$workdir" >&2
  exit 70
}

for case_file in "$root"/tests/cases/*.sh; do
  name=$(basename "$case_file" .sh)
  case $name in
    *"$filter"*) ;;
    *) continue ;;
  esac
  casedir=$workdir/$name
  mkdir -p "$casedir"
  if (
    cd "$casedir" || exit 1
    . "$root/tests/lib.sh"
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

printf '\n%s passed, %s failed (shell: %s)\n' "$passed" "$failed" "$shell_under_test"
if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
