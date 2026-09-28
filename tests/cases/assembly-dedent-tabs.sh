# Dedent compares leading whitespace as a string, so a body indented with
# tabs, or with a tab followed by spaces, keeps its relative shape.
printf 'nested:\n\tif true; then\n\t  echo inner\n\tfi\n' >Spurfile

run -n nested
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
if true; then
  echo inner
fi
EOF
