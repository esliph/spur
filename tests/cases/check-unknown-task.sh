spurfile <<'EOF'
build:
  echo building
EOF

run --check nope
assert_status 67
assert_stderr_has 'spur: unknown task: nope'
