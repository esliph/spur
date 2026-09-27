spurfile <<'EOF'
db-reset: ## recreate the database
  echo resetting

docker.build:
  echo building

unit_test:
  echo testing

step2:
  echo stepping
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

run unit_test
assert_status 0
assert_stdout_is <<'EOF'
testing
EOF

run step2
assert_status 0
assert_stdout_is <<'EOF'
stepping
EOF
