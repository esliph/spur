spurfile <<'EOF'
raw:
  echo "$IMAGE ${x:-y} $(date) $$"
EOF

run -n raw
assert_status 0
assert_stdout_has 'echo "$IMAGE ${x:-y} $(date) $$"'
