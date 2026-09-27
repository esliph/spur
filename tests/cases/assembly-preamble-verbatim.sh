spurfile <<'EOF'
greeting=hello

log() {
  printf '>> %s\n' "$1"
}

hello:
  log "$greeting"
EOF

run -n hello
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
greeting=hello

log() {
  printf '>> %s\n' "$1"
}
log "$greeting"
EOF
