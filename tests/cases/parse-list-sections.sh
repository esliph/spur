spurfile <<'EOF'
build: ## build the image
  docker build .

##@ Quality
test: ## run the tests
  pytest -q

##@ Release and deploy
deploy-production: ## ship it
  ./deploy.sh
rollback:
  ./rollback.sh
EOF

run --list
assert_status 0
assert_stdout_is <<EOF
Spurfile: $PWD/Spurfile

Tasks
  build               build the image

Quality
  test                run the tests

Release and deploy
  deploy-production   ship it
  rollback
EOF
