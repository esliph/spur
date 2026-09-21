spurfile <<'EOF'
env:
  printf 'task=%s\n' "$SPUR_TASK"
  printf 'root=%s\n' "$SPUR_ROOT"
  printf 'from=%s\n' "$SPUR_INVOCATION_DIR"
  [ -f "$SPUR_BIN" ] && printf 'bin=ok\n'
EOF

base=$PWD
mkdir -p sub
cd sub || fail "cannot enter sub"

run env
assert_status 0
assert_stdout_is <<EOF
task=env
root=$base
from=$base/sub
bin=ok
EOF
