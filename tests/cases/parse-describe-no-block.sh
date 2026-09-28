spurfile <<'EOF'
build: ## build it
  echo building
lint:
  echo linting
## Only a long description.
fmt:
  echo formatting
EOF

run --describe build
assert_status 0
assert_stdout_is <<'EOF'
build: build it
EOF

run --describe lint
assert_status 0
assert_stdout_is <<'EOF'
lint: (no description)
EOF

run --describe fmt
assert_status 0
assert_stdout_is <<'EOF'
fmt

Only a long description.
EOF
