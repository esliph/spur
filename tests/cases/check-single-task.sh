spurfile <<'EOF'
ok:
  echo fine

broken:
  if true; then
    echo never closed
EOF

run --check ok
assert_status 0
[ -s stderr ] && fail "stderr is not empty"

run --check broken
assert_status 65
assert_stderr_has 'spur broken:'
