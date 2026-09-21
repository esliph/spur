cat > spurfile <<'EOF'
build:
  echo hi
EOF

# On a case-insensitive filesystem (macOS, Windows) the lowercase file also
# answers to "Spurfile", and that is the spelling the runner probes first.
expected_name=spurfile
if [ -f Spurfile ]; then
  expected_name=Spurfile
fi

base=$PWD
run
assert_status 0
assert_stdout_has "Spurfile: $base/$expected_name"
