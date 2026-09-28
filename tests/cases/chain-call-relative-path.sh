# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
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
capture "$shell_under_test" ../vendored-spur build

assert_status 0
assert_stdout_is <<'EOF'
installing deps
building
EOF
