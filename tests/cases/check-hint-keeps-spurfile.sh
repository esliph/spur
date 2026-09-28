# The hint after a failed check names the same Spurfile, so following it
# shows the task that failed, not a task of another file or none at all.
mkdir ci
cat >ci/tasks.spur <<'EOF'
broken:
  if true; then
EOF

run -f ci/tasks.spur --check
assert_status 65
assert_stderr_has "spur: run 'spur -f $PWD/ci/tasks.spur -n broken' to see the assembled script"

run -C ci -f tasks.spur --check broken
assert_status 65
assert_stderr_has "spur: run 'spur -f $PWD/ci/tasks.spur -n broken' to see the assembled script"

mkdir 'with space'
cp ci/tasks.spur 'with space/Spurfile'
run -C 'with space' --check
assert_status 65
assert_stderr_has "spur: run 'spur -f \"$PWD/with space/Spurfile\" -n broken' to see the assembled script"
