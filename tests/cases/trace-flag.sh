spurfile <<'EOF'
IMAGE=myapp:latest

show:
  echo "building $IMAGE"
EOF

run -x show
assert_status 0
assert_stdout_has 'building myapp:latest'
# The trace shows the expanded command, with a lean PS4. Shells disagree on
# quoting a word that holds a space (dash prints it bare, bash quotes it), so
# accept either spelling.
assert_stderr_matches "^[$] echo '?building myapp:latest'?\$"
