# Only ##@ at column zero opens a section; indented, it is body text.
spurfile <<'EOF'
build: ## build it
  echo building
  ##@ not a section
  echo done
EOF

run --list
assert_status 0
assert_stdout_lacks 'not a section'

run -n build
assert_status 0
assert_stdout_has '##@ not a section'
assert_stdout_has 'echo done'
