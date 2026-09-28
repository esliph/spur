# A section that ends up with no task is not listed.
spurfile <<'EOF'
##@ Nothing here yet
##@ Build
build: ## build it
  echo building

##@ Empty at the end
EOF

run --list
assert_status 0
assert_stdout_is <<EOF
Spurfile: $PWD/Spurfile

Build
  build   build it
EOF
