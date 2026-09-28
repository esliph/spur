spurfile <<'EOF'
build:
  echo building
EOF

for flag in -l -n -x --check; do
  run --names "$flag" build
  assert_status 64
  assert_stderr_has "spur: --names cannot be combined with -l, -n, -x or --check"
  assert_stdout_lacks 'building'
  run "$flag" --names build
  assert_status 64
  assert_stderr_has "spur: --names cannot be combined with -l, -n, -x or --check"
done
