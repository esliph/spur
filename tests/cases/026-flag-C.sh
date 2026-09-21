mkdir -p api
cat > api/Spurfile <<'EOF'
build:
  echo hi
EOF

base=$PWD
run -C api
assert_status 0
assert_stdout_has "Spurfile: $base/api/Spurfile"
