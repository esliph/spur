# lint-all is a prefix match but farther than the rest, so it ranks last;
# mint is as close as the three shown, but comes fourth in file order.
spurfile <<'EOF'
lint-all:
  echo all
hint:
  echo hint
lints:
  echo lints
list:
  echo list
mint:
  echo mint
EOF

run lint
assert_status 67
assert_stderr_has 'spur: did you mean: hint, lints, list?'
