spurfile <<'EOF'
build:
  echo one

build:
  echo two
EOF

run --list
assert_status 65
assert_stderr_has 'Spurfile:4: duplicate task: build'
