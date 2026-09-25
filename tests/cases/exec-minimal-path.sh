# The runner needs sh, awk, dirname, basename and cat (for --help), and
# nothing else: every path through it works with only those on PATH.
# $runner and $shell_under_test come from tests/run.sh.
# shellcheck disable=SC2154
spurfile <<'EOF'
greet: ## say hello
  echo "hello $1"

outer:
  spur greet world
EOF

# Each tool is a script that execs the real one by its absolute path. A copy
# or a symlink would do on Linux, but not under MSYS (Git Bash), where a
# copied binary no longer finds the DLLs that sit next to the original.
mkdir bin
for tool in sh awk dirname basename cat; do
  real=$(command -v "$tool") || fail "no $tool on PATH"
  # shellcheck disable=SC2016  # "$@" is for the wrapper, not expanded here
  printf '#!/bin/sh\nexec '\''%s'\'' "$@"\n' "$real" >"bin/$tool"
  chmod +x "bin/$tool"
done
shell=$(command -v "$shell_under_test") || fail "cannot resolve $shell_under_test"

minimal() { capture env PATH="$PWD/bin" "$shell" "$runner" "$@"; }

minimal --list
assert_status 0
assert_stdout_has 'say hello'

minimal --help
assert_status 0
assert_stdout_has 'Usage:'

minimal greet you
assert_status 0
assert_stdout_is <<'EOF'
hello you
EOF

minimal --check
assert_status 0

# spur called from a task: the child runner sees the same PATH.
minimal outer
assert_status 0
assert_stdout_is <<'EOF'
hello world
EOF

# Negative control: without awk the runner cannot parse, which proves the
# restricted PATH is the only one it sees.
rm bin/awk
minimal --list
assert_status 127
