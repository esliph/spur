mkdir -p other
cat > other/custom.spur <<'EOF'
where:
  pwd
EOF

base=$PWD
run -f other/custom.spur where
assert_status 0
assert_stdout_is <<EOF
$base/other
EOF
