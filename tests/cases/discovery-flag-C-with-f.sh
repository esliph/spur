# -C applies before -f is resolved: -f names a file relative to the -C
# directory, and the task runs from there.
mkdir sub
cat >sub/custom.spur <<'EOF'
where:
  pwd
EOF

base=$PWD
run -C sub -f custom.spur where
assert_status 0
assert_stdout_is <<EOF
$base/sub
EOF
