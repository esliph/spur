# The harness removes its work directory whether its cases pass or fail. The
# directory's path holds a space, so every use of it must be quoted.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf ':\n' >fake/tests/cases/a-pass.sh
printf 'exit 1\n' >fake/tests/cases/b-fail.sh
mkdir 'tmp dir'

capture env SPUR_TEST_TMPDIR="$PWD/tmp dir" "$shell_under_test" fake/tests/run.sh a-pass
assert_status 0
set -- 'tmp dir'/*
if [ -e "$1" ]; then fail "left behind by a passing run: $1"; fi

capture env SPUR_TEST_TMPDIR="$PWD/tmp dir" "$shell_under_test" fake/tests/run.sh b-fail
assert_status 1
set -- 'tmp dir'/*
if [ -e "$1" ]; then fail "left behind by a failing run: $1"; fi
