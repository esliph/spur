spurfile <<'EOF'
build:
  echo building
EOF

for flag in -l -n -x; do
  run --check "$flag" build
  assert_status 64
  assert_stderr_has "spur: --check cannot be combined with -l, -n or -x"
  run "$flag" --check build
  assert_status 64
  assert_stderr_has "spur: --check cannot be combined with -l, -n or -x"
done
