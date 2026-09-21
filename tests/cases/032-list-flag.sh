spurfile <<'EOF'
build: ## build it
  echo building
EOF

# -l lists and exits even when a task name follows.
run -l build
assert_status 0
assert_stdout_has '  build   build it'
assert_stdout_lacks 'building'
