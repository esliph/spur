# Shared by the behavior harness (tests/run.sh) and the benchmark harness
# (tests/bench/run.sh). Sourced, never run.
# shellcheck disable=SC2034  # $names and $count are read by the harnesses

# select_names DIR FILTER [EXCLUDE] -- set $names to the selected script names
# in DIR (file names without .sh, space-separated, in glob order, which is
# alphabetical) and $count to how many there are. When DIR/FILTER.sh exists,
# it is selected alone; otherwise every name containing FILTER is, and an
# empty FILTER selects everything. EXCLUDE is a name never selected.
select_names() {
  names=
  count=0
  if [ -n "$2" ] && [ "$2" != "${3:-}" ] && [ -f "$1/$2.sh" ]; then
    names=$2
    count=1
    return 0
  fi
  for f in "$1"/*.sh; do
    [ -f "$f" ] || continue # an empty DIR leaves the pattern itself
    n=${f##*/}
    n=${n%.sh}
    [ "$n" != "${3:-}" ] || continue
    case $n in
      *"$2"*)
        names=${names:+$names }$n
        count=$((count + 1))
        ;;
    esac
  done
}
