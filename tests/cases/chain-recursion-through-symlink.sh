# The same Spurfile reached through a symlinked directory is still the same
# Spurfile. Where ln -s copies instead of linking (Git Bash without symlink
# support), there is no symlink to go through and nothing to check.
spurfile <<'EOF'
a:
  spur -C link a
EOF

ln -s . link 2>/dev/null
if [ ! -L link ]; then exit 0; fi

run a
assert_status 68
assert_stderr_has 'spur: recursion detected: a -> a'
