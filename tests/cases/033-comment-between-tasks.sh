spurfile <<'EOF'
build: ## build it
  echo building

# This comment sits at column zero between two tasks.
test: ## test it
  echo testing
EOF

run --list
assert_status 0
assert_stdout_has '  build   build it'
assert_stdout_has '  test    test it'
