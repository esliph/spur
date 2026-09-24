# An empty ##@ falls back to the default section, and whitespace around a
# title is not part of it. A heading prints only when the section changes.
spurfile <<'EOF'
build: ## build it
  echo building

##@
test: ## test it
  echo testing

##@Release   
deploy: ## ship it
  echo deploying

##@   
lint: ## lint it
  echo linting
EOF

run --list
assert_status 0
assert_stdout_is <<EOF
Spurfile: $PWD/Spurfile

Tasks
  build    build it
  test     test it

Release
  deploy   ship it

Tasks
  lint     lint it
EOF
