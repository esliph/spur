spurfile <<'EOF'
build:
  echo hi
EOF

base=$PWD
run
assert_status 0
assert_stdout_has "Spurfile: $base/Spurfile"
