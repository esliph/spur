spurfile <<'EOF'
build:
  echo building
EOF

for flag in -l -n -x --check --names; do
  run --describe "$flag" build
  assert_status 64
  assert_stderr_has 'spur: --describe cannot be combined with -l, -n, -x, --check or --names'
  run "$flag" --describe build
  assert_status 64
  assert_stderr_has 'spur: --describe cannot be combined with -l, -n, -x, --check or --names'
done
