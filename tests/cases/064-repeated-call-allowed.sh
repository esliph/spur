spurfile <<'EOF'
leaf:
  echo leaf

twice:
  spur leaf
  spur leaf
EOF

run twice
assert_status 0
assert_stdout_is <<'EOF'
leaf
leaf
EOF
