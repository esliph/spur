spurfile <<'EOF'
nested:
    if true; then
      echo inner
    fi
EOF

run -n nested
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
if true; then
  echo inner
fi
EOF
