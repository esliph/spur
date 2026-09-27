# A third of a name shorter than three characters is no edit at all, so a
# short name is only suggested for a prefix, never for an unrelated letter.
spurfile <<'EOF'
a:
  echo a
b:
  echo b
ab:
  echo ab
EOF

run c
assert_status 67
assert_stderr_lacks 'did you mean'

run ab
assert_status 0

run a
assert_status 0
