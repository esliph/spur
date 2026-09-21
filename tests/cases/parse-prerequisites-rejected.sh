spurfile <<'EOF'
build: deps
  echo building
EOF

run --list
assert_status 65
assert_stderr_has 'Spurfile:1: task header takes no prerequisites: build'
