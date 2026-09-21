spurfile <<'EOF'
boom:
  exit 42
EOF

run boom
assert_status 42

# A runner error code must never be mistaken for a task code.
run -f missing
assert_status 66
