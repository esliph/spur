# Only lines that start with exactly "##" are documentation: a "###" banner
# or heading above the block is an ordinary comment and stays out of it.
spurfile <<'EOF'
##########
### Heading
## First doc line.
## Second doc line.
build: ## build it
  echo building

## Kept.
### Between
deploy:
  echo deploying
EOF

run --describe build
assert_status 0
assert_stdout_is <<'EOF'
build: build it

First doc line.
Second doc line.
EOF

run --describe deploy
assert_status 0
assert_stdout_is <<'EOF'
deploy: (no description)
EOF
