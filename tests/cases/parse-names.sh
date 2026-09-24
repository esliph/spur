spurfile <<'EOF'
build: ## build the image
  docker build .

##@ Quality
test: ## run the tests
  pytest -q

##@ Release and deploy
deploy-production: ## ship it
  ./deploy.sh
docker.push:
  docker push
EOF

# One name per line in file order: no header, no sections, no descriptions.
run --names
assert_status 0
assert_stdout_is <<'EOF'
build
test
deploy-production
docker.push
EOF
assert_stderr_lacks 'Spurfile'
