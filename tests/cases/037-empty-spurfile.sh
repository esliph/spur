spurfile <<'EOF'
# nothing here but a comment
EOF

run --list
assert_status 0
assert_stdout_has '(no tasks defined)'
