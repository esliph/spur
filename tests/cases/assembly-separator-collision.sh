# The parser hands the preamble and the bodies over in one output, split by
# a marker line that it picks so that no emitted line starts with it. Lines
# that start like its first candidates (#spur, #spur-, #spur--) are content,
# in the preamble and in a body, and must reach the script unchanged.
spurfile <<'EOF'
#spur
#spur- preamble
first:
  echo one
  #spur first
  #spur-- first

second:
  echo two

broken:
  if true; then
EOF

run -n first
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
#spur
#spur- preamble
echo one
#spur first
#spur-- first
EOF

run -n second
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
#spur
#spur- preamble
echo two
EOF

# Checking every task: only the broken one is reported, under its own name.
run --check
assert_status 65
assert_stderr_has 'spur broken:'
assert_stderr_lacks 'spur first'
assert_stderr_lacks 'spur second'
assert_stderr_lacks 'spur (preamble)'
