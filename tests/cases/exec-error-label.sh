spurfile <<'EOF'
broken:
  no-such-command-anywhere
EOF

run broken
assert_status 127
assert_stderr_has 'spur broken'
