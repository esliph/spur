# A case gets no stdin: the harness closes it, so a case that reads it by
# mistake reads nothing, instead of hanging the suite or taking input meant
# for someone else.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
cat >fake/tests/cases/a-reads.sh <<'EOT'
if read -r line; then
  echo "read the harness's stdin: $line"
  exit 1
fi
EOT
printf 'leaked\n' >input

capture "$shell_under_test" fake/tests/run.sh <input
assert_status 0
assert_stdout_has 'ok   a-reads'
