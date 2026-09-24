spurfile <<'EOF'
build:
  echo building
EOF

run nope
assert_status 67
assert_stderr_lacks 'did you mean'
assert_stderr_has 'spur: unknown task: nope'
assert_stderr_has "spur: run 'spur --list'"
