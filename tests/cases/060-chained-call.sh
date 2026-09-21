spurfile <<'EOF'
deps:
  echo installing deps

build:
  spur deps
  echo building
EOF

run build
assert_status 0
assert_stdout_is <<'EOF'
installing deps
building
EOF
