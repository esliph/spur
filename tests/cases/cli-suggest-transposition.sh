spurfile <<'EOF'
test:
  echo testing
EOF

run tset
assert_status 67
assert_stderr_has 'spur: did you mean: test?'
