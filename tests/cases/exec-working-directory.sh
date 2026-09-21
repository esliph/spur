spurfile <<'EOF'
where:
  pwd
EOF

base=$PWD
mkdir -p deep/deeper
cd deep/deeper || fail "cannot enter deep/deeper"

run where
assert_status 0
assert_stdout_is <<EOF
$base
EOF
