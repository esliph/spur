spurfile <<'EOF'
build: ## build it
  echo building
lint:
  echo linting
EOF

# Like -l, --names lists and exits even when a task name follows.
run --names build
assert_status 0
assert_stdout_is <<'EOF'
build
lint
EOF
