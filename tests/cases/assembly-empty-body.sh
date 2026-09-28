# A task header with no body is legal: it assembles to the prelude and the
# preamble alone, and running it does nothing and succeeds.
spurfile <<'EOF'
READY=yes

placeholder: ## nothing yet
next:
  echo next
EOF

run -n placeholder
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
READY=yes
EOF

run placeholder
assert_status 0
assert_stdout_is <<'EOF'
EOF
