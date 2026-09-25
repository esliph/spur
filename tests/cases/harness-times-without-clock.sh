# A date whose %N prints nothing, like busybox in Alpine, leaves whole
# seconds that look like a number. That is not a clock: the harness reports
# timings unavailable and runs without them.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf ':\n' >fake/tests/cases/a-one.sh
mkdir bin
printf '#!/bin/sh\necho 1790332364\n' >bin/date
chmod +x bin/date

capture env PATH="$PWD/bin:$PATH" SPUR_TEST_TIMES=1 "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stderr_has 'timings unavailable'
assert_stdout_is <<EOF
ok   a-one

1 passed, 0 failed (shell: $shell_under_test, jobs: 1)
EOF
