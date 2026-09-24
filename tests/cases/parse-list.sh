spurfile <<'EOF'
IMAGE=myapp:latest

build: ## build the image
  docker build -t "$IMAGE" .

test: ## run the tests
  pytest -q "$@"

deploy:
  ./deploy.sh
EOF

run --list
assert_status 0
assert_stdout_is <<EOF
Spurfile: $PWD/Spurfile

Tasks
  build    build the image
  test     run the tests
  deploy
EOF
