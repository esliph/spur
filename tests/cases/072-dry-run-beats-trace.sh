spurfile <<'EOF'
show:
  echo visible
EOF

run -n -x show
assert_status 0
assert_stdout_has 'set -x'
# Printed, not executed: the echo never ran.
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
PS4='$ '
set -x
echo visible
EOF
