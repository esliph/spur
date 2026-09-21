# $runner and $shell_under_test come from tests/run.sh; $status is read by
# assert_status in tests/lib.sh.
# shellcheck disable=SC2154,SC2034
spurfile <<'EOF'
read-line:
  read line
  printf 'got=[%s]\n' "$line"
EOF

printf 'from stdin\n' | "$shell_under_test" "$runner" read-line >stdout 2>stderr
status=$?
assert_status 0
assert_stdout_is <<'EOF'
got=[from stdin]
EOF
