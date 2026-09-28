spurfile <<'EOF'
# nothing here but a comment
EOF

# No placeholder line: a script looping over the output sees nothing.
run --names
assert_status 0
assert_stdout_is <<'EOF'
EOF
