spurfile <<'EOF'
touch preamble-ran

build:
  touch body-ran
  echo "$(touch substitution-ran)"
EOF

run --check
assert_status 0
assert_stdout_is <<'EOF'
EOF
for marker in preamble-ran body-ran substitution-ran; do
  [ -e "$marker" ] && fail "--check executed something: $marker exists"
done
exit 0
