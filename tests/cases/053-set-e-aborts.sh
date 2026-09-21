spurfile <<'EOF'
chain:
  echo first
  false
  echo never
EOF

run chain
assert_status 1
assert_stdout_has 'first'
assert_stdout_lacks 'never'
