spurfile <<'EOF'
VAR=1
## Documents build.
build: ## build it
  echo building
EOF

# Above the first task the block is also preamble, as any comment is.
run --describe build
assert_status 0
assert_stdout_is <<'EOF'
build: build it

Documents build.
EOF

run -n build
assert_status 0
assert_stdout_has '## Documents build.'
