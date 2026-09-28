spurfile <<'EOF'
log() {
  printf '>> %s\n' "$1"
}

build:
  log building
  log done
EOF

run build
assert_status 0
assert_stdout_is <<'EOF'
>> building
>> done
EOF
