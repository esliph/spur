# A second signal while the harness waits for its workers stops the workers
# too: once the harness has exited, no worker may go on to the remaining
# cases (their directory is gone, so each would print errors). TERM is sent
# twice; a shell started in the background ignores SIGINT.
# $shell_under_test comes from tests/run.sh; $status is read by assert_status
# in tests/lib.sh.
# shellcheck disable=SC2154,SC2034
fake_suite
cat >fake/tests/cases/a-slow.sh <<'EOF'
: >"$FLAGS/a-started"
sleep 3
EOF
for n in b-next c-next d-next; do
  printf ':\n' >"fake/tests/cases/$n.sh"
done
mkdir flags tmp

FLAGS=$PWD/flags SPUR_TEST_TMPDIR=$PWD/tmp SPUR_TEST_JOBS=1 \
  "$shell_under_test" fake/tests/run.sh >stdout 2>stderr &
pid=$!
tries=0
until [ -f flags/a-started ]; do
  tries=$((tries + 1))
  if [ "$tries" -gt 20 ]; then
    kill "$pid"
    fail "a-slow never started"
  fi
  sleep 1
done
kill -TERM "$pid"
sleep 1
kill -TERM "$pid"
wait "$pid"
status=$?

assert_status 130
# Let a-slow's sleep run out: a surviving worker would move on to b-next.
sleep 4
if [ -s stderr ]; then fail "a worker outlived the harness: $(cat stderr)"; fi
set -- tmp/*
if [ -e "$1" ]; then fail "work directory left behind: $1"; fi
