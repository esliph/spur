spurfile <<'EOF'
ok:
  echo fine

broken:
  if true; then
    echo never closed
EOF

run --check
assert_status 65
assert_stderr_has 'spur broken:'
assert_stderr_has "spur: run 'spur -n broken' to see the assembled script"
assert_stderr_lacks 'spur ok:'
