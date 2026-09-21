spurfile <<'EOF'
build:
  echo hi
EOF

base=$PWD
mkdir -p deep/deeper
cd deep/deeper || fail "cannot enter deep/deeper"

run
assert_status 0
assert_stdout_has "Spurfile: $base/Spurfile"
