spurfile <<'EOF'
lint:
  printf 'lint args=[%s]\n' "$*"

check:
  spur lint --fix
EOF

run check
assert_status 0
assert_stdout_is <<'EOF'
lint args=[--fix]
EOF
