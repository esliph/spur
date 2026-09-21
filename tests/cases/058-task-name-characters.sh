spurfile <<'EOF'
db-reset: ## recreate the database
  echo resetting

docker.build:
  echo building
EOF

run db-reset
assert_status 0
assert_stdout_is <<'EOF'
resetting
EOF

run docker.build
assert_status 0
assert_stdout_is <<'EOF'
building
EOF
