# A task of the same name in another Spurfile is another task: the guard
# keys each frame on the Spurfile as well as the name.
spurfile <<'EOF'
install:
  echo root
  spur -C sub install
EOF

mkdir sub
cat > sub/Spurfile <<'EOF'
install:
  echo sub
EOF

run install
assert_status 0
assert_stdout_is <<'EOF'
root
sub
EOF
