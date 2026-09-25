# Without a sub-second clock the benchmark harness refuses to print numbers:
# it exits 69 with a message and runs nothing. The fake date prints whole
# seconds, as busybox in Alpine does for +%s%N.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf 'measure --version\n' >fake/tests/bench/only.sh
mkdir bin
printf '#!/bin/sh\necho 1790332364\n' >bin/date
chmod +x bin/date

capture env PATH="$PWD/bin:$PATH" "$shell_under_test" fake/tests/bench/run.sh
assert_status 69
assert_stderr_has 'no sub-second clock'
assert_stdout_lacks 'only'
