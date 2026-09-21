# Assertion helpers for the spur test suite.
#
# Sourced by tests/run.sh inside each case's own temporary directory. The
# variables $runner and $shell_under_test come from the harness.
# shellcheck disable=SC2154  # $runner and $shell_under_test come from tests/run.sh

fail() {
  printf 'assertion failed: %s\n' "$*"
  printf -- '--- stdout ---\n'
  cat stdout 2>/dev/null
  printf -- '--- stderr ---\n'
  cat stderr 2>/dev/null
  exit 1
}

# Write ./Spurfile from stdin.
spurfile() { cat > Spurfile; }

# Run the runner under test; capture stdout, stderr and the exit status.
run() {
  "$shell_under_test" "$runner" "$@" >stdout 2>stderr
  status=$?
  return 0
}

assert_status() {
  [ "$status" = "$1" ] || fail "expected exit status $1, got $status"
}

# Compare stdout with the heredoc given on stdin, byte for byte.
assert_stdout_is() {
  cat > expected
  diff -u expected stdout || fail "stdout differs from expected"
}

assert_stdout_has() {
  grep -qF -- "$1" stdout || fail "stdout does not contain: $1"
}

assert_stdout_lacks() {
  grep -qF -- "$1" stdout && fail "stdout unexpectedly contains: $1"
  return 0
}

assert_stdout_matches() {
  grep -qE -- "$1" stdout || fail "stdout does not match: $1"
}

assert_stderr_has() {
  grep -qF -- "$1" stderr || fail "stderr does not contain: $1"
}

assert_stderr_lacks() {
  grep -qF -- "$1" stderr && fail "stderr unexpectedly contains: $1"
  return 0
}

assert_stderr_matches() {
  grep -qE -- "$1" stderr || fail "stderr does not match: $1"
}
