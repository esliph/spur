# A Spurfile saved with CRLF line endings runs as if it had LF: no carriage
# return reaches the header, the preamble or the assembled script.
# shellcheck disable=SC2016  # $GREETING is for the task shell, not expanded here
printf 'GREETING=hello\r\n\r\nbuild: ## build it\r\n  echo "$GREETING there"\r\n' >Spurfile

run build
assert_status 0
assert_stdout_is <<'EOF'
hello there
EOF

run -n build
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
GREETING=hello
echo "$GREETING there"
EOF
