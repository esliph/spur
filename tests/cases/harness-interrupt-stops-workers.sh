# A TERM mid-run stops the harness cleanly: the case in progress finishes, no
# other case starts, the work directory is removed, and the exit status is
# 143. INT goes through the same code (exit 130) but cannot be sent from
# here: a shell started in the background ignores SIGINT.
# $shell_under_test comes from tests/run.sh; $status is read by assert_status
# in tests/lib.sh.
# shellcheck disable=SC2154,SC2034
fake_suite
cat >fake/tests/cases/a-slow.sh <<'EOF'
: >"$FLAGS/a-started"
sleep 3
EOF
cat >fake/tests/cases/b-next.sh <<'EOF'
: >"$FLAGS/b-started"
EOF
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
wait "$pid"
status=$?

assert_status 143
if [ -f flags/b-started ]; then fail "a case started after the TERM"; fi
if [ -s stdout ]; then fail "an interrupted run printed a report"; fi
set -- tmp/*
if [ -e "$1" ]; then fail "work directory left behind: $1"; fi
