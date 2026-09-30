spurfile <<'EOF'
a:
  spur -C sub b
EOF

mkdir sub
cat > sub/Spurfile <<'EOF'
b:
  spur -C .. a
EOF

run a
assert_status 68
assert_stderr_has 'spur: recursion detected: a -> b -> a'
