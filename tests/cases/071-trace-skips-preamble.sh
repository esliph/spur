spurfile <<'EOF'
SECRET=preamble-value
helper() { echo helped; }

show:
  echo visible
EOF

run -x show
assert_status 0
assert_stderr_lacks 'SECRET=preamble-value'
assert_stderr_has '$ echo visible'
