spurfile <<'EOF'
build:
  echo building
deploy:
  echo deploying
EOF

run dep
assert_status 67
assert_stderr_has 'spur: did you mean: deploy?'
