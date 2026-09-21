spurfile <<'EOF'
FOO=bar

hello: ## greet
  echo "$FOO"
EOF

run -n hello
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
FOO=bar
echo "$FOO"
EOF
