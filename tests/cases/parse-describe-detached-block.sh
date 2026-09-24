spurfile <<'EOF'
## Separated by a blank line.

a: ## task a
  echo a
## Separated by a plain comment.
# a plain comment
b: ## task b
  echo b
## Separated by a section.
##@ Section
c: ## task c
  echo c
EOF

# Only a block right above the header belongs to the task.
for t in a b c; do
  run --describe "$t"
  assert_status 0
  assert_stdout_is <<EOF
$t: task $t
EOF
done
