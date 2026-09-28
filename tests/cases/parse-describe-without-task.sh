spurfile <<'EOF'
build:
  echo building
EOF

run --describe
assert_status 64
assert_stderr_has 'spur: no task given'
