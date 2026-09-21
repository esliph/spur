# $runner and $shell_under_test come from tests/run.sh; $status is read by
# assert_status in tests/lib.sh.
# shellcheck disable=SC2154,SC2034
spurfile <<'EOF'
deps:
  echo installing deps

build:
  spur deps
  echo building
EOF

cp "$runner" ./vendored-spur
chmod +x ./vendored-spur

# Invoked by a relative path, outside the PATH, from another directory.
mkdir -p sub
cd sub || fail "cannot enter sub"
"$shell_under_test" ../vendored-spur build >stdout 2>stderr
status=$?

assert_status 0
assert_stdout_is <<'EOF'
installing deps
building
EOF
