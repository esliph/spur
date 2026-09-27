# The cost of --check, which assembles and parses every task: an awk and an
# sh -n per task (a second sh -n when the task has a heredoc), so 50 tasks
# rather than 500.
i=0
while [ "$i" -lt 50 ]; do
  printf 'task-%s: ## t\n  echo %s\n' "$i" "$i"
  i=$((i + 1))
done >Spurfile
measure --check
