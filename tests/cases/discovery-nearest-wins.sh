spurfile <<'EOF'
where:
  echo outer
  pwd
EOF

base=$PWD
mkdir -p inner/deeper
cat >inner/Spurfile <<'EOF'
where:
  echo inner
  pwd
EOF
cd inner/deeper || fail "cannot enter inner/deeper"

run where
assert_status 0
assert_stdout_is <<EOF
inner
$base/inner
EOF
