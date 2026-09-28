# A second signal while the harness waits for its workers stops everything
# the workers started: the worker shells, the case in progress and whatever
# that case runs. A case ignores SIGINT (it runs in the background), so it
# would otherwise outlive the harness, and a worker would go on to the next
# case in a directory that is gone. TERM is sent twice, and the exit status
# is the one of the second TERM; a shell started in the background ignores
# SIGINT.
# $shell_under_test comes from tests/run.sh; $status is read by assert_status
# in tests/lib.sh.
# shellcheck disable=SC2154,SC2034
fake_suite
cat >fake/tests/cases/a-slow.sh <<'EOF'
: >"$FLAGS/a-started"
sleep 3
: >"$FLAGS/a-finished"
EOF
for n in b-next c-next d-next; do
  # $FLAGS is for the fake case to expand when it runs, not for this printf.
  # shellcheck disable=SC2016
  printf ': >"$FLAGS/%s-started"\n' "$n" >"fake/tests/cases/$n.sh"
done
mkdir flags tmp

FLAGS=$PWD/flags SPUR_TEST_TMPDIR=$PWD/tmp SPUR_TEST_JOBS=1 \
  "$shell_under_test" fake/tests/run.sh >stdout 2>stderr &
pid=$!
wait_for flags/a-started || {
  kill "$pid"
  fail "a-slow never started"
}
kill -TERM "$pid"
# The first TERM is being handled once the harness has asked the workers to
# stop; only then is the second one a second signal.
wait_for "tmp/spur-tests.$pid/.stop" || {
  kill "$pid"
  fail "the first TERM was never handled"
}
kill -TERM "$pid"
wait "$pid"
status=$?

assert_status 143
# Let a-slow's sleep run out: a surviving case would finish it, a surviving
# worker would move on to b-next.
sleep 4
if [ -f flags/a-finished ]; then fail "the case in progress outlived the harness"; fi
set -- flags/*-next-started
if [ -e "$1" ]; then fail "a worker started a case after the harness exited: $1"; fi
if [ -s stderr ]; then fail "a worker outlived the harness: $(cat stderr)"; fi
set -- tmp/*
if [ -e "$1" ]; then fail "work directory left behind: $1"; fi
