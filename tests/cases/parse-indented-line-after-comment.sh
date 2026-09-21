# A comment at column zero closes the open body, so the indented line that
# follows belongs to no task. Without this case the parser's diagnostic for
# that state is never exercised.
spurfile <<'EOF'
build:
  echo one
# this comment closes the body above
  echo two
EOF

run --list
assert_status 65
assert_stderr_has 'Spurfile:4: indented line does not belong to any task'
