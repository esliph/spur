spurfile <<'EOF'
if true; then
  X=1

build:
  echo building

test:
  echo testing
EOF

run --check
assert_status 65
assert_stderr_has 'spur (preamble):'
assert_stderr_lacks 'spur build:'
assert_stderr_lacks 'spur test:'
assert_stderr_lacks "'spur -n"
