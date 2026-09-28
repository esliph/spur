spurfile <<'EOF'
build:
  echo building
EOF

run -n buld
assert_status 67
assert_stderr_has 'spur: did you mean: build?'

run --describe buld
assert_status 67
assert_stderr_has 'spur: did you mean: build?'

run --check buld
assert_status 67
assert_stderr_has 'spur: did you mean: build?'
