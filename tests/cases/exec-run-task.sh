spurfile <<'EOF'
PREFIX=hello

greet:
  echo "$PREFIX world"
EOF

run greet
assert_status 0
assert_stdout_is <<'EOF'
hello world
EOF
