# The task sees the caller's environment unchanged, apart from the SPUR_*
# variables the runner exports: the runner's own variables all start with
# spur_ or SPUR_, so they cannot overwrite a variable the caller exported.
# $runner comes from tests/run.sh.
# shellcheck disable=SC2154
spurfile <<'EOF'
show:
  for v in VERSION task mode flags head script seen last on m conflict \
      others NL HINT PRELUDE PARSER_OUT AWK_PARSER code self dir parent \
      line name chain frame check_failed list_opt dry_opt trace_opt; do
    eval "printf '%s=%s\n' \$v \"\${$v-unset}\""
  done
EOF

capture env VERSION=x task=x mode=x flags=x head=x script=x seen=x last=x \
  on=x m=x conflict=x others=x NL=x HINT=x PRELUDE=x PARSER_OUT=x \
  AWK_PARSER=x code=x self=x dir=x parent=x line=x name=x chain=x frame=x \
  check_failed=x list_opt=x dry_opt=x trace_opt=x \
  "$shell_under_test" "$runner" show
assert_status 0
assert_stdout_is <<'EOF'
VERSION=x
task=x
mode=x
flags=x
head=x
script=x
seen=x
last=x
on=x
m=x
conflict=x
others=x
NL=x
HINT=x
PRELUDE=x
PARSER_OUT=x
AWK_PARSER=x
code=x
self=x
dir=x
parent=x
line=x
name=x
chain=x
frame=x
check_failed=x
list_opt=x
dry_opt=x
trace_opt=x
EOF

# The list above is the runner's variables as they once were. So that a new
# variable cannot escape it, every name the runner assigns, loops over or
# reads into must be in its own namespace. Assignments inside the awk
# program have spaces around "=" and are not matched.
stray=$(sed -n \
  -e 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' \
  -e 's/^[[:space:]]*for \([A-Za-z_][A-Za-z0-9_]*\) in .*/\1/p' \
  -e 's/.*read -r \([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' \
  "$runner" | grep -v -e '^spur_' -e '^SPUR_' | sort -u)
if [ -n "$stray" ]; then fail "runner variables outside spur_/SPUR_: $stray"; fi
