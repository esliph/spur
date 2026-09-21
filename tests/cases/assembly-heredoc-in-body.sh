# A heredoc survives the dedent when its terminator is indented with the rest
# of the body: dedent moves it back to column zero, which is where the shell
# looks for it. The opposite shape is pinned by
# parse-heredoc-terminator-at-column-zero.
#
# The case heredocs use OUTER so that TEXT can appear at column zero in the
# expected output without ending them.
spurfile <<'OUTER'
gen:
  cat <<TEXT
  hello from the body
  TEXT
  echo after
OUTER

run -n gen
assert_status 0
assert_stdout_is <<'OUTER'
set -e
spur() { "$SPUR_BIN" "$@"; }
cat <<TEXT
hello from the body
TEXT
echo after
OUTER

run gen
assert_status 0
assert_stdout_is <<'OUTER'
hello from the body
after
OUTER
