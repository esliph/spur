spurfile <<'EOF'
gapped:
  echo one

  echo two

other:
  echo three
EOF

run -n gapped
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
echo one

echo two
EOF
