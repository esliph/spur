# The cost of --check, which assembles and parses every task: three processes
# per task, so 50 tasks rather than 500 (500 take minutes per run).
i=0
while [ "$i" -lt 50 ]; do
  printf 'task-%s: ## t\n  echo %s\n' "$i" "$i"
  i=$((i + 1))
done >Spurfile
measure --check
