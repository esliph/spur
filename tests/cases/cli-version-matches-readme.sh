# The README's install section shows what `spur -v` prints. `spur release`
# changes both; this keeps a hand edit from moving only one of them.
# $root comes from tests/run.sh.
# shellcheck disable=SC2154
run -v
assert_status 0
if ! grep -qxF "$stdout" "$root/README.md"; then
  fail "README.md does not show the line: $stdout"
fi
