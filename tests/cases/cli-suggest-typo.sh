spurfile <<'EOF'
build:
  echo building
EOF

run buld
assert_status 67
assert_stderr_has 'spur: unknown task: buld'
assert_stderr_has 'spur: did you mean: build?'
assert_stderr_has "spur: run 'spur --list'"
