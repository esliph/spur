mkdir -p other
cat > other/custom.spur <<'EOF'
build:
  echo hi
EOF

base=$PWD
run -f other/custom.spur
assert_status 0
assert_stdout_has "Spurfile: $base/other/custom.spur"
