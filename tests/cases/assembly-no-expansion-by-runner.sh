spurfile <<'EOF'
raw:
  echo "$IMAGE ${x:-y} $(date) $$"
EOF

run -n raw
assert_status 0
# shellcheck disable=SC2016  # the single quotes are the point: nothing may expand
assert_stdout_has 'echo "$IMAGE ${x:-y} $(date) $$"'
