# Body extraction from a large Spurfile: the task is the last of 500.
i=0
while [ "$i" -lt 500 ]; do
  printf 'task-%s: ## t\n  echo %s\n' "$i" "$i"
  i=$((i + 1))
done >Spurfile
measure task-499
