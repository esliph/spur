spurfile <<'EOF'
build:
  echo building
this is not a task header
EOF

# The diagnostic goes to stderr only, so a completion that discards stderr
# offers nothing instead of offering the error text.
run --names
assert_status 65
assert_stderr_has 'Spurfile:3: syntax error: expected a task header'
assert_stdout_is <<'EOF'
EOF
