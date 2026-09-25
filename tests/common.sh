# Shared by the behavior harness (tests/run.sh) and the benchmark harness
# (tests/bench/run.sh). Sourced, never run.
# shellcheck disable=SC2034  # $names, $count, $clock and $ms are read by the harnesses

# select_names DIR FILTER [EXCLUDE] -- set $names to the selected script names
# in DIR (file names without .sh, space-separated, in glob order, which is
# alphabetical) and $count to how many there are. When DIR/FILTER.sh exists,
# it is selected alone; otherwise every name containing FILTER is, and an
# empty FILTER selects everything. EXCLUDE is a name never selected.
select_names() {
  names=
  count=0
  case $2 in */*) return 0 ;; esac # a filter is a name, never a path
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

# detect_clock -- set $clock to 1 when `date +%s%N` prints nanoseconds since
# the epoch. GNU date does; macOS prints a literal N; the busybox date in
# Alpine 3.20 prints nothing for %N, which leaves whole seconds that look
# like a number. Nanoseconds since the epoch have at least 19 digits.
detect_clock() {
  clock=
  _now=$(date +%s%N 2>/dev/null)
  case $_now in
    '' | *[!0-9]*) ;;
    *) [ "${#_now}" -lt 19 ] || clock=1 ;;
  esac
}

# now_ms -- set $ms to the current time in milliseconds. Only meaningful once
# detect_clock has set $clock.
now_ms() {
  ms=$(date +%s%N)
  ms=${ms%??????}
}
