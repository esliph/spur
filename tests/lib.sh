# Assertion helpers for the spur test suite.
#
# Sourced by tests/run.sh inside each case's own temporary directory. The
# variables $root, $runner and $shell_under_test come from the harness.
# shellcheck disable=SC2154  # $root, $runner and $shell_under_test come from tests/run.sh

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

# load_file FILE -- set $loaded to the contents of FILE with the read builtin,
# so no process is started. A last line without a trailing newline is kept;
# the final newline itself is dropped, which no substring match can see.
load_file() {
  loaded=
  _nl=
  while IFS= read -r _line || [ -n "$_line" ]; do
    loaded=$loaded$_nl$_line
    _nl='
'
  done <"$1"
}

# capture COMMAND [ARGS...] -- run any command; leave its output in the files
# stdout and stderr and in the variables $stdout and $stderr, and its exit
# status in $status. The has/lacks assertions read the variables, so a case
# that runs something other than the runner (the harness, a vendored copy)
# goes through capture too.
capture() {
  "$@" >stdout 2>stderr
  status=$?
  load_file stdout
  stdout=$loaded
  load_file stderr
  stderr=$loaded
  return 0
}

# Run the runner under test; capture stdout, stderr and the exit status.
run() { capture "$shell_under_test" "$runner" "$@"; }

assert_status() {
  [ "$status" = "$1" ] || fail "expected exit status $1, got $status"
}

# Compare stdout with the heredoc given on stdin, byte for byte.
assert_stdout_is() {
  cat > expected
  diff -u expected stdout || fail "stdout differs from expected"
}

# The has/lacks assertions: a quoted "$1" in a case pattern is literal, so
# they match fixed strings like grep -F, without starting grep.
assert_stdout_has() {
  case $stdout in
    *"$1"*) ;;
    *) fail "stdout does not contain: $1" ;;
  esac
}

assert_stdout_lacks() {
  case $stdout in
    *"$1"*) fail "stdout unexpectedly contains: $1" ;;
  esac
}

assert_stdout_matches() {
  grep -qE -- "$1" stdout || fail "stdout does not match: $1"
}

assert_stderr_has() {
  case $stderr in
    *"$1"*) ;;
    *) fail "stderr does not contain: $1" ;;
  esac
}

assert_stderr_lacks() {
  case $stderr in
    *"$1"*) fail "stderr unexpectedly contains: $1" ;;
  esac
}

assert_stderr_matches() {
  grep -qE -- "$1" stderr || fail "stderr does not match: $1"
}

# fake_suite -- copy the harness and the runner into ./fake, with empty
# tests/cases and tests/bench for the case to fill. The copied harness finds
# its root through $0, so it runs the fake suite. Only harness- cases use it.
fake_suite() {
  mkdir -p fake/tests/cases fake/tests/bench
  cp "$root/spur" fake/spur
  cp "$root/tests/run.sh" "$root/tests/lib.sh" "$root/tests/common.sh" fake/tests/
}
