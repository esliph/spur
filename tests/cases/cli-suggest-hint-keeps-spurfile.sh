# The hint after an unknown task names the same Spurfile, so following it
# lists the tasks of the file that was searched.
mkdir ci
cat >ci/tasks.spur <<'EOF'
build:
  echo building
EOF

run -f ci/tasks.spur nope
assert_status 67
assert_stderr_has "spur: run 'spur -f $PWD/ci/tasks.spur --list' to see the available tasks"
