spurfile <<'EOF'
build:
  echo building
EOF

run -n
assert_status 64
assert_stderr_has 'spur: no task given'

run -x
assert_status 64
assert_stderr_has 'spur: no task given'
