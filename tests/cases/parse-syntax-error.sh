spurfile <<'EOF'
build:
  echo building
this is not a task header
EOF

run --list
assert_status 65
assert_stderr_has 'Spurfile:3: syntax error: expected a task header'
