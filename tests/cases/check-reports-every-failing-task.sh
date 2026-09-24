spurfile <<'EOF'
first:
  if true; then
    echo never closed

second:
  echo "unterminated

third:
  echo fine
EOF

run --check
assert_status 65
assert_stderr_has "spur: run 'spur -n first' to see the assembled script"
assert_stderr_has "spur: run 'spur -n second' to see the assembled script"
assert_stderr_lacks "'spur -n third'"
