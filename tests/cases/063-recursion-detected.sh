spurfile <<'EOF'
a:
  spur b

b:
  spur a
EOF

run a
assert_status 68
assert_stderr_has 'spur: recursion detected: a -> b -> a'
