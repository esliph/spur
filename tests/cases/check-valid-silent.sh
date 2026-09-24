spurfile <<'EOF'
GREETING=hello

build: ## build it
  if [ -n "$GREETING" ]; then
    echo "$GREETING"
  fi

test:
  cat <<END
  body
  END
EOF

run --check
assert_status 0
assert_stdout_is <<'EOF'
EOF
[ -s stderr ] && fail "stderr is not empty"
exit 0
