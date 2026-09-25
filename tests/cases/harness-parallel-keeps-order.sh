# Cases run in parallel workers, and the report is alphabetical and reads the
# same as a serial run, whatever order the cases finish in.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
# a-slow is first in the report and, in parallel, the last to finish.
# b-one waits until a-slow has started, then records whether a-slow was
# still running: proof that the workers really overlap.
cat >fake/tests/cases/a-slow.sh <<'EOT'
: >"$FLAGS/a-started"
sleep 2
: >"$FLAGS/a-done"
EOT
cat >fake/tests/cases/b-one.sh <<'EOT'
i=0
until [ -f "$FLAGS/a-started" ]; do
  i=$((i + 1))
  [ "$i" -le 5 ] || exit 1
  sleep 1
done
if [ -f "$FLAGS/a-done" ]; then echo serial; else echo parallel; fi >"$FLAGS/b-saw"
EOT
for n in c-two d-three e-four f-five; do
  printf 'echo %s\n' "$n" >"fake/tests/cases/$n.sh"
done
mkdir flags

capture env FLAGS="$PWD/flags" SPUR_TEST_JOBS=4 "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stdout_is <<EOT
ok   a-slow
ok   b-one
ok   c-two
ok   d-three
ok   e-four
ok   f-five

6 passed, 0 failed (shell: $shell_under_test, jobs: 4)
EOT
read -r saw <flags/b-saw
[ "$saw" = parallel ] || fail "with 4 workers, b-one ran after a-slow: $saw"

rm flags/*
capture env FLAGS="$PWD/flags" SPUR_TEST_JOBS=1 "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stdout_is <<EOT
ok   a-slow
ok   b-one
ok   c-two
ok   d-three
ok   e-four
ok   f-five

6 passed, 0 failed (shell: $shell_under_test, jobs: 1)
EOT
read -r saw <flags/b-saw
[ "$saw" = serial ] || fail "with 1 worker, b-one ran during a-slow: $saw"
