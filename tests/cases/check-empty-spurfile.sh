: > Spurfile

run --check
assert_status 0
assert_stdout_is <<'EOF'
EOF
