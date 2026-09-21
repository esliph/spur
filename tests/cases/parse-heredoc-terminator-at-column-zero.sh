# The mirror of assembly-heredoc-in-body. A terminator left at column zero is
# content at column zero, so it ends the task body and is then read as a task
# header that is not one. Failing loudly beats silently truncating the task,
# and this is the shape people copy in from a standalone script.
spurfile <<'OUTER'
gen:
  cat <<TEXT
  hello
TEXT
  echo after
OUTER

run --list
assert_status 65
assert_stderr_has 'Spurfile:4: syntax error: expected a task header'
