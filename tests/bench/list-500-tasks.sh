# Parser scaling in list mode: 500 tasks with a description each.
i=0
while [ "$i" -lt 500 ]; do
  printf 'task-%s: ## t\n  echo %s\n' "$i" "$i"
  i=$((i + 1))
done >Spurfile
measure --list
