# Parallel Harness, Timings and Benchmarks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make spur's behavior suite run in parallel with deterministic output, add per-case timings on demand, add a benchmark harness, and pin the runner's real dependencies with `exec-minimal-path`.

**Architecture:** `tests/common.sh` (new, sourced) holds case selection and the clock for both harnesses. `tests/run.sh` becomes select → run (N background workers, round-robin, one status file per case) → report (alphabetical, from the status files). `tests/lib.sh` gains `capture` and loads captured output into `$stdout`/`$stderr` so `has`/`lacks` assertions match with `case` instead of forking `grep`. `tests/bench/run.sh` runs scenarios serially and prints min/mean/max. Harness self-tests run a copy of the harnesses (`fake_suite`) on cases they write themselves.

**Tech Stack:** strict POSIX sh, POSIX awk (runner only), `date +%s%N` as the clock, shellcheck 0.11 (via Docker locally), GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-24-test-suite-design.md` — read it alongside this plan. Both files live on `feat/suite-test` only and are removed before merge.

## Global Constraints

- Strict POSIX sh everywhere, including `tests/`. No bashisms. `shellcheck -s sh` clean; every `# shellcheck disable=` carries its justification on the same or the previous line.
- The runner (`spur`) is **not modified** by this plan (the runner is out of scope). It may depend on `sh`, `awk`, `dirname`, `basename`, `cat` only.
- No test framework, no JUnit, no coverage tooling. The harness may use ordinary tools (`sed`, `diff`, `grep -E`, `sort`, `getconf`, `date`).
- `sh tests/run.sh [name|group-]` keeps its interface: exact name first, then substring; selecting nothing prints `no test matches: <arg>` to stderr and exits 64.
- Summary line format: `N passed, M failed (shell: <shell>, jobs: <workers>)`. The `N passed, M failed` prefix must stay.
- Everything written in English (code, comments, commits). Conventional Commits (`test:`, `test(harness):`, `test(bench):`, `docs:`, `ci:`), ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- LF line endings only (`.gitattributes` forces it). After writing files on Windows, `git ls-files --eol tests/` must show `i/lf w/lf` for every file.
- Every behavior change comes with a test; every new case is seen red (against missing code or a deliberately broken harness/runner) before it is trusted.
- **Case-writing trap:** a case's exit status is its last command's. Never end a case (or a branch of it) with `[ ... ] && fail ...` — when the test is false the case fails. Use `if [ ... ]; then fail ...; fi`.
- **Local environment (Windows + Git Bash):** run every test command through Git Bash, never PowerShell. `sh` is bash in POSIX mode, so `SPUR_TEST_SHELL=dash` is the real POSIX check. shellcheck and busybox run through Docker:
  - shellcheck: `MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/mnt" -w /mnt koalaman/shellcheck-alpine:stable shellcheck -s sh <files>`
  - busybox: `MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/work" -w /work alpine:3.20 sh -c "apk add --no-cache diffutils >/dev/null && sh tests/run.sh"`

## Deviations from the spec (confirmed by measurement on this machine)

1. **`exec-minimal-path` builds `./bin/` from wrapper scripts** (`#!/bin/sh` + `exec '/usr/bin/awk' "$@"`), not copies or symlinks. Measured: under Git Bash a copied or symlinked `awk.exe` in another directory fails with `error while loading shared libraries` (it no longer finds the MSYS DLLs next to the original); wrappers work. Wrappers work on Linux and busybox too.
2. **Clock detection requires at least 19 digits**, not just "all digits". Measured: busybox `date` in `alpine:3.20` prints `1790332364` for `+%s%N` (`%N` expands to nothing), which the spec's rule would accept as a clock. So under busybox the timings are reported unavailable.
3. **`check-500-tasks` becomes `check-50-tasks`.** Measured: `spur --check` on 500 tasks takes 2 m 36 s per run here (three processes per task); 11 runs would take half an hour. 50 tasks keeps the scenario meaningful. (This is exactly the kind of cost the benchmarks exist to expose; optimizing it is out of scope.)
4. **Ctrl-C:** workers are asynchronous lists, and in a non-interactive shell those **ignore SIGINT**, so the spec's "a terminal Ctrl-C reaches them too" does not hold. The harness's INT/TERM trap writes `$workdir/.stop`; workers check it before each case, finish the case in progress, and stop; the harness waits for them, then the EXIT trap cleans up. INT exits 130, TERM 143. A second Ctrl-C stops waiting.
5. **`capture CMD...`** is added to `tests/lib.sh`, and `run` is built on it. Because `has`/`lacks` now read `$stdout`/`$stderr`, a case that invokes a command by hand would assert against stale variables. `harness-selects-by-name` and `chain-call-relative-path` move to `capture` (the spec said the former was unchanged; its assertions are unchanged, only the invocation is).
6. **Cases run with stdin closed** (`</dev/null`): with parallel workers, an inherited stdin would be shared between cases.
7. **`now_ms` sets `$ms`** instead of printing it (saves a subshell per call); clock detection is a function, `detect_clock`, called only when timing is needed, so a normal run pays no `date` fork.
8. **Benchmark harness without a clock exits 69** (sysexits `EX_UNAVAILABLE`); the spec only asked for "a clear message".
9. **`SPUR_TEST_JOBS` set but empty means unset** (the default), like `${VAR:-}` everywhere else; leading zeros (`07`) are refused because `$((...))` would read them as octal.
10. **Extra `harness-` cases** beyond the spec's table: `harness-helpers-literal-match`, `harness-case-stdin-closed`, `harness-interrupt-stops-workers`, `harness-times-without-clock`, `harness-bench-iterations-invalid`, `harness-bench-without-clock` (see Review Focus).

## Review Focus

1. **A `date` that ignores `%N`** (busybox in Alpine, the CI busybox job) → timings must be reported unavailable, never computed from whole seconds. Pinned by `harness-times-without-clock` (Task 4) and `harness-bench-without-clock` (Task 5), both with a fake `date` on `PATH`.
2. **Ctrl-C or TERM mid-run** → no new case starts, the running one finishes, the work directory is removed, exit 130/143. Pinned by `harness-interrupt-stops-workers` (Task 3), with TERM (a backgrounded shell ignores INT, so INT cannot be sent from a case; both signals share the code path).
3. **`SPUR_TEST_TIMES=1 ./spur test` or `SPUR_TEST_JOBS=…` leaking into cases** → a `harness-` case that starts a nested harness would get timed or oddly-sized output and break byte-exact comparisons. `run.sh` unsets both after reading them; pinned by the fake case inside `harness-times` (Task 4).
4. **Assertion text containing `*`, `?` or `[`** → must still match literally after `grep -F` becomes `case`. Pinned by `harness-helpers-literal-match` (Task 1).
5. **A case that reads stdin** → with parallel workers it would steal another case's input or hang the suite. Pinned by `harness-case-stdin-closed` (Task 2).

---

## File Structure

| Path | Responsibility | Task |
|---|---|---|
| `tests/lib.sh` | helpers; `capture`, `load_file`, var-based `has`/`lacks`, `fake_suite` | 1, 2, 5 |
| `tests/common.sh` (new) | `select_names`, `detect_clock`, `now_ms` | 2, 4 |
| `tests/run.sh` | behavior harness: select → parallel workers → report | 2, 3, 4 |
| `tests/bench/run.sh` (new) | benchmark harness, `measure` | 5 |
| `tests/bench/*.sh` (new) | six scenarios | 5 |
| `tests/cases/harness-*.sh` (new) | harness self-tests | 1–5 |
| `tests/cases/exec-minimal-path.sh` (new) | runner dependency diet | 6 |
| `tests/cases/harness-selects-by-name.sh`, `tests/cases/chain-call-relative-path.sh` | move to `capture` | 1 |
| `README.md`, `AGENTS.md`, `CONTRIBUTING.md` | dependency statement (6), suite docs (7) | 6, 7 |
| `Spurfile`, `.github/workflows/ci.yml` | `bench` task, lint list, bench smoke job | 7 |
| `.claude/skills/spur-tests/SKILL.md`, `references/coverage-map.md` | skill refresh | 7 |

---

### Task 1: `tests/lib.sh` — `capture`, variables, fork-free `has`/`lacks`

**Files:**
- Modify: `tests/lib.sh` (whole file)
- Modify: `tests/cases/harness-selects-by-name.sh`, `tests/cases/chain-call-relative-path.sh`
- Test: `tests/cases/harness-helpers-literal-match.sh` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `capture COMMAND [ARGS...]` — runs the command; writes files `./stdout`, `./stderr`; sets `$stdout`, `$stderr` (file contents, final newline dropped) and `$status`; returns 0.
  - `run ARGS...` — `capture "$shell_under_test" "$runner" ARGS...`.
  - `load_file FILE` — sets `$loaded` to FILE's contents using only the `read` builtin.
  - `assert_{stdout,stderr}_{has,lacks} TEXT` — literal substring test on `$stdout`/`$stderr`.

- [ ] **Step 1: Record the baseline wall time (before any change)**

Run (Git Bash, repo root): `time sh tests/run.sh >/dev/null`
Expected: all cases pass; `real` around 80 s. Write the number down — Task 8 reports it next to the new one.

- [ ] **Step 2: Write the failing case**

Create `tests/cases/harness-helpers-literal-match.sh`:

```sh
# capture fills $stdout and $stderr, and the has/lacks assertions match them
# as fixed strings, the way grep -F did: characters that mean something in a
# shell pattern are matched as themselves. A last line with no trailing
# newline is kept.

capture printf 'a*c [x] ?\nlast line, no newline'
assert_status 0
assert_stdout_has 'a*c'
assert_stdout_has '[x] ?'
assert_stdout_has 'last line, no newline'
# As shell patterns these would match the output; as fixed strings they do not.
assert_stdout_lacks 'a?c'
assert_stdout_lacks '[a]'
assert_stderr_lacks 'a*c'

# A failing assertion fails the case: run each in a subshell and expect it
# to exit non-zero.
if (assert_stdout_has 'absent') >/dev/null; then
  fail "assert_stdout_has passed on absent text"
fi
if (assert_stdout_lacks 'a*c') >/dev/null; then
  fail "assert_stdout_lacks passed on present text"
fi

# A second capture replaces what the first one loaded.
capture sh -c 'printf "oops\n" >&2; exit 3'
assert_status 3
assert_stderr_has 'oops'
assert_stdout_lacks 'a*c'
```

- [ ] **Step 3: Run it to verify it fails**

Run: `sh tests/run.sh harness-helpers-literal-match`
Expected: `FAIL harness-helpers-literal-match` with `assertion failed: expected exit status 0, got ` (`capture` does not exist yet).

- [ ] **Step 4: Rewrite `tests/lib.sh`**

Replace the whole file with:

```sh
# Assertion helpers for the spur test suite.
#
# Sourced by tests/run.sh inside each case's own temporary directory. The
# variables $root, $runner and $shell_under_test come from the harness.
# shellcheck disable=SC2154  # $root, $runner and $shell_under_test come from tests/run.sh

fail() {
  printf 'assertion failed: %s\n' "$*"
  printf -- '--- stdout ---\n'
  cat stdout 2>/dev/null
  printf -- '--- stderr ---\n'
  cat stderr 2>/dev/null
  exit 1
}

# Write ./Spurfile from stdin.
spurfile() { cat > Spurfile; }

# load_file FILE -- set $loaded to the contents of FILE with the read builtin,
# so no process is started. A last line without a trailing newline is kept;
# the final newline itself is dropped, which no substring match can see.
load_file() {
  loaded=
  _nl=
  while IFS= read -r _line || [ -n "$_line" ]; do
    loaded=$loaded$_nl$_line
    _nl='
'
  done <"$1"
}

# capture COMMAND [ARGS...] -- run any command; leave its output in the files
# stdout and stderr and in the variables $stdout and $stderr, and its exit
# status in $status. The has/lacks assertions read the variables, so a case
# that runs something other than the runner (the harness, a vendored copy)
# goes through capture too.
capture() {
  "$@" >stdout 2>stderr
  status=$?
  load_file stdout
  stdout=$loaded
  load_file stderr
  stderr=$loaded
  return 0
}

# Run the runner under test; capture stdout, stderr and the exit status.
run() { capture "$shell_under_test" "$runner" "$@"; }

assert_status() {
  [ "$status" = "$1" ] || fail "expected exit status $1, got $status"
}

# Compare stdout with the heredoc given on stdin, byte for byte.
assert_stdout_is() {
  cat > expected
  diff -u expected stdout || fail "stdout differs from expected"
}

# The has/lacks assertions: a quoted "$1" in a case pattern is literal, so
# they match fixed strings like grep -F, without starting grep.
assert_stdout_has() {
  case $stdout in
    *"$1"*) ;;
    *) fail "stdout does not contain: $1" ;;
  esac
}

assert_stdout_lacks() {
  case $stdout in
    *"$1"*) fail "stdout unexpectedly contains: $1" ;;
  esac
}

assert_stdout_matches() {
  grep -qE -- "$1" stdout || fail "stdout does not match: $1"
}

assert_stderr_has() {
  case $stderr in
    *"$1"*) ;;
    *) fail "stderr does not contain: $1" ;;
  esac
}

assert_stderr_lacks() {
  case $stderr in
    *"$1"*) fail "stderr unexpectedly contains: $1" ;;
  esac
}

assert_stderr_matches() {
  grep -qE -- "$1" stderr || fail "stderr does not match: $1"
}
```

- [ ] **Step 5: Move the hand-invoking cases to `capture`**

In `tests/cases/harness-selects-by-name.sh`, replace the header comment's last two lines and the `harness()` function:

```sh
# The harness itself: a case is selected by its exact name, then by substring.
# Only cases that never start the harness again may be selected here.
# $root and $shell_under_test come from tests/run.sh.
# shellcheck disable=SC2154
harness() { capture "$shell_under_test" "$root/tests/run.sh" "$@"; }
```

(the rest of the file is unchanged).

In `tests/cases/chain-call-relative-path.sh`, replace the header:

```sh
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
```

and replace the two lines

```sh
"$shell_under_test" ../vendored-spur build >stdout 2>stderr
status=$?
```

with

```sh
capture "$shell_under_test" ../vendored-spur build
```

Leave `tests/cases/exec-stdin-is-free.sh` alone: it pipes into the runner (a pipeline would run `capture` in a subshell and lose `$status`) and asserts only through files (`assert_stdout_is`).

- [ ] **Step 6: Run the new case, the migrated ones, then the suite under sh and dash**

Run: `sh tests/run.sh harness- && sh tests/run.sh chain-call-relative-path`
Expected: `ok` for each, exit 0.
Run: `sh tests/run.sh && SPUR_TEST_SHELL=dash sh tests/run.sh`
Expected: `82 passed, 0 failed` twice.

- [ ] **Step 7: shellcheck**

Run: `MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/mnt" -w /mnt koalaman/shellcheck-alpine:stable shellcheck -s sh spur tests/run.sh tests/lib.sh tests/cases/*.sh`
Expected: no output, exit 0.

- [ ] **Step 8: Commit**

```bash
git add tests/lib.sh tests/cases/harness-helpers-literal-match.sh tests/cases/harness-selects-by-name.sh tests/cases/chain-call-relative-path.sh
git commit -m "test: match has/lacks assertions without forking grep

run now goes through capture, which also loads stdout and stderr into
\$stdout and \$stderr; the has/lacks assertions match those with case.
Cases that invoke a command by hand use capture.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `tests/common.sh` and the parallel `tests/run.sh`

**Files:**
- Create: `tests/common.sh`
- Modify: `tests/run.sh` (whole file)
- Modify: `tests/lib.sh` (append `fake_suite`)
- Test (new): `tests/cases/harness-parallel-keeps-order.sh`, `harness-failure-reported.sh`, `harness-jobs-invalid.sh`, `harness-cleans-workdir.sh`, `harness-case-stdin-closed.sh`

**Interfaces:**
- Consumes: `capture` (Task 1).
- Produces:
  - `select_names DIR FILTER [EXCLUDE]` (in `tests/common.sh`) — sets `$names` (space-separated, glob order = alphabetical) and `$count`. Exact `DIR/FILTER.sh` wins; else substring; EXCLUDE is never selected.
  - `fake_suite` (in `tests/lib.sh`) — creates `./fake/spur`, `./fake/tests/{run.sh,lib.sh,common.sh}`, empty `./fake/tests/cases/` and `./fake/tests/bench/`.
  - `tests/run.sh` internals used by Tasks 3–4: variables `workdir`, `workers`, `names`; functions `run_case NAME`, `run_worker K`; status file `$workdir/NAME.status` holding `STATUS` then optionally ` MILLISECONDS`.

- [ ] **Step 1: Create `tests/common.sh`**

```sh
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
```

- [ ] **Step 2: Append `fake_suite` to `tests/lib.sh`**

```sh

# fake_suite -- copy the harness and the runner into ./fake, with empty
# tests/cases and tests/bench for the case to fill. The copied harness finds
# its root through $0, so it runs the fake suite. Only harness- cases use it.
fake_suite() {
  mkdir -p fake/tests/cases fake/tests/bench
  cp "$root/spur" fake/spur
  cp "$root/tests/run.sh" "$root/tests/lib.sh" "$root/tests/common.sh" fake/tests/
}
```

- [ ] **Step 3: Write the five failing cases**

`tests/cases/harness-parallel-keeps-order.sh`:

```sh
# Cases run in parallel workers, and the report is alphabetical and reads the
# same as a serial run, whatever order the cases finish in.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
# a-slow is first in the report and, in parallel, the last to finish.
# b-one waits until a-slow has started, then records whether a-slow was
# still running: proof that the workers really overlap.
cat >fake/tests/cases/a-slow.sh <<'EOF'
: >"$FLAGS/a-started"
sleep 2
: >"$FLAGS/a-done"
EOF
cat >fake/tests/cases/b-one.sh <<'EOF'
i=0
until [ -f "$FLAGS/a-started" ]; do
  i=$((i + 1))
  [ "$i" -le 5 ] || exit 1
  sleep 1
done
if [ -f "$FLAGS/a-done" ]; then echo serial; else echo parallel; fi >"$FLAGS/b-saw"
EOF
for n in c-two d-three e-four f-five; do
  printf 'echo %s\n' "$n" >"fake/tests/cases/$n.sh"
done
mkdir flags

capture env FLAGS="$PWD/flags" SPUR_TEST_JOBS=4 "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stdout_is <<EOF
ok   a-slow
ok   b-one
ok   c-two
ok   d-three
ok   e-four
ok   f-five

6 passed, 0 failed (shell: $shell_under_test, jobs: 4)
EOF
read -r saw <flags/b-saw
[ "$saw" = parallel ] || fail "with 4 workers, b-one ran after a-slow: $saw"

rm flags/*
capture env FLAGS="$PWD/flags" SPUR_TEST_JOBS=1 "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stdout_is <<EOF
ok   a-slow
ok   b-one
ok   c-two
ok   d-three
ok   e-four
ok   f-five

6 passed, 0 failed (shell: $shell_under_test, jobs: 1)
EOF
read -r saw <flags/b-saw
[ "$saw" = serial ] || fail "with 1 worker, b-one ran during a-slow: $saw"
```

`tests/cases/harness-failure-reported.sh`:

```sh
# A failing case is reported as FAIL with its output indented under it, the
# others as ok, and the harness exits 1.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf ':\n' >fake/tests/cases/a-pass.sh
printf 'echo first line\necho second line\nexit 3\n' >fake/tests/cases/b-fail.sh
printf ':\n' >fake/tests/cases/c-pass.sh

capture env SPUR_TEST_JOBS=2 "$shell_under_test" fake/tests/run.sh
assert_status 1
assert_stdout_is <<EOF
ok   a-pass
FAIL b-fail
     first line
     second line
ok   c-pass

2 passed, 1 failed (shell: $shell_under_test, jobs: 2)
EOF
```

`tests/cases/harness-jobs-invalid.sh`:

```sh
# SPUR_TEST_JOBS must be a positive integer; anything else is a usage error
# before any case runs. Empty means unset, and more workers than cases are
# capped at the number of cases.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf ':\n' >fake/tests/cases/a-one.sh

# 07 is refused too: $((...)) would read it as octal.
for jobs in 0 abc -1 07 '4 2'; do
  capture env SPUR_TEST_JOBS="$jobs" "$shell_under_test" fake/tests/run.sh
  assert_status 64
  assert_stderr_has "SPUR_TEST_JOBS must be a positive integer, got: $jobs"
  assert_stdout_lacks 'passed'
done

capture env SPUR_TEST_JOBS= "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stdout_has '1 passed, 0 failed'

capture env SPUR_TEST_JOBS=99 "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stdout_has "1 passed, 0 failed (shell: $shell_under_test, jobs: 1)"
```

`tests/cases/harness-cleans-workdir.sh`:

```sh
# The harness removes its work directory whether its cases pass or fail. The
# directory's path holds a space, so every use of it must be quoted.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf ':\n' >fake/tests/cases/a-pass.sh
printf 'exit 1\n' >fake/tests/cases/b-fail.sh
mkdir 'tmp dir'

capture env SPUR_TEST_TMPDIR="$PWD/tmp dir" "$shell_under_test" fake/tests/run.sh a-pass
assert_status 0
set -- 'tmp dir'/*
if [ -e "$1" ]; then fail "left behind by a passing run: $1"; fi

capture env SPUR_TEST_TMPDIR="$PWD/tmp dir" "$shell_under_test" fake/tests/run.sh b-fail
assert_status 1
set -- 'tmp dir'/*
if [ -e "$1" ]; then fail "left behind by a failing run: $1"; fi
```

`tests/cases/harness-case-stdin-closed.sh`:

```sh
# A case gets no stdin: the harness closes it, so a case that reads it by
# mistake reads nothing, instead of hanging the suite or taking input meant
# for someone else.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
cat >fake/tests/cases/a-reads.sh <<'EOF'
if read -r line; then
  echo "read the harness's stdin: $line"
  exit 1
fi
EOF
printf 'leaked\n' >input

capture "$shell_under_test" fake/tests/run.sh <input
assert_status 0
assert_stdout_has 'ok   a-reads'
```

- [ ] **Step 4: Run them to verify they fail**

Run: `sh tests/run.sh harness-`
Expected:
- `FAIL harness-parallel-keeps-order`, `FAIL harness-failure-reported` — stdout differs (the summary has no `jobs:`).
- `FAIL harness-jobs-invalid` — `expected exit status 64, got 0`.
- `FAIL harness-case-stdin-closed` — `expected exit status 0, got 1` (the fake case read `leaked`).
- `ok   harness-cleans-workdir` — it pins behavior the current harness already has; Step 7 turns it red on purpose.

- [ ] **Step 5: Rewrite `tests/run.sh`**

Replace the whole file with:

```sh
#!/bin/sh
# Behavior tests for spur.
#
# Usage:
#   sh tests/run.sh [name]
#
# With a name, the case of exactly that name runs alone; when there is none,
# the name is a substring filter over the case names. Selecting nothing is a
# usage error (exit 64).
#
# The selected cases run in parallel workers, each case in a subshell in its
# own directory, with stdin closed. The report comes once every case has
# finished, in alphabetical order, so it reads the same with any number of
# workers.
#
# Environment:
#   SPUR_TEST_SHELL     shell used to run the runner under test (default: sh)
#   SPUR_TEST_TMPDIR    where the per-case directories go (default: /tmp)
#   SPUR_TEST_JOBS      number of workers (default: the number of CPUs);
#                       1 runs the cases one at a time
# shellcheck disable=SC2154  # $names and $count come from tests/common.sh

case $0 in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
root=$(cd "$here/.." && pwd)
runner=$root/spur
shell_under_test=${SPUR_TEST_SHELL:-sh}
filter=${1:-}
workdir=${SPUR_TEST_TMPDIR:-/tmp}/spur-tests.$$

# shellcheck source=tests/common.sh
. "$root/tests/common.sh"

# SPUR_TEST_JOBS is a positive integer; empty means unset. Leading zeros are
# refused, because $((...)) reads 010 as octal.
if [ -n "${SPUR_TEST_JOBS:-}" ]; then
  workers=$SPUR_TEST_JOBS
  case $workers in
    *[!0-9]* | 0*)
      printf 'SPUR_TEST_JOBS must be a positive integer, got: %s\n' "$workers" >&2
      exit 64
      ;;
  esac
else
  workers=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
  case $workers in
    '' | *[!0-9]* | 0*) workers=1 ;;
  esac
fi

# The runner exports its own state to child processes. When the suite is
# started through spur itself (./spur test), that state would leak into every
# case, so start from a clean slate. The harness's own controls go too: a
# case that starts a harness gets the defaults unless it asks otherwise.
unset SPUR_BIN SPUR_ROOT SPUR_INVOCATION_DIR SPUR_TASK SPUR_STACK SPUR_TEST_JOBS

select_names "$root/tests/cases" "$filter"
if [ "$count" -eq 0 ]; then
  printf 'no test matches: %s\n' "$filter" >&2
  exit 64
fi
[ "$workers" -le "$count" ] || workers=$count

# shellcheck disable=SC2317,SC2329  # invoked through the EXIT and INT traps
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT

mkdir -p "$workdir" || {
  printf 'cannot create %s\n' "$workdir" >&2
  exit 70
}

# run_case NAME -- run one case, leaving its output in NAME.log and its exit
# status in NAME.status, next to its directory.
run_case() {
  mkdir "$workdir/$1"
  (
    cd "$workdir/$1" || exit 1
    . "$root/tests/lib.sh"
    # shellcheck source=/dev/null
    . "$root/tests/cases/$1.sh"
  ) >"$workdir/$1.log" 2>&1 </dev/null
  rc=$?
  printf '%s\n' "$rc" >"$workdir/$1.status"
}

# run_worker K -- run, one after another, the selected cases whose position in
# the list is K modulo the number of workers. Neighbours share a group and
# cost about the same, so round-robin spreads each group over the workers.
run_worker() {
  i=0
  # Case names are file names: no spaces, no glob characters.
  # shellcheck disable=SC2086
  for name in $names; do
    if [ $((i % workers)) -eq "$1" ]; then
      run_case "$name"
    fi
    i=$((i + 1))
  done
}

k=0
while [ "$k" -lt "$workers" ]; do
  run_worker "$k" &
  k=$((k + 1))
done
wait

passed=0
failed=0
# Case names are file names: no spaces, no glob characters.
# shellcheck disable=SC2086
for name in $names; do
  rc=
  if [ -f "$workdir/$name.status" ]; then
    read -r rc <"$workdir/$name.status"
  fi
  if [ "$rc" = 0 ]; then
    passed=$((passed + 1))
    printf 'ok   %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$name"
    sed 's/^/     /' "$workdir/$name.log"
  fi
done

printf '\n%s passed, %s failed (shell: %s, jobs: %s)\n' \
  "$passed" "$failed" "$shell_under_test" "$workers"
if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
```

- [ ] **Step 6: Run the harness group, then the whole suite under sh and dash**

Run: `sh tests/run.sh harness- && SPUR_TEST_SHELL=dash sh tests/run.sh harness-`
Expected: every `harness-` case `ok`, exit 0.
Run: `sh tests/run.sh; SPUR_TEST_SHELL=dash sh tests/run.sh`
Expected: `87 passed, 0 failed (shell: sh, jobs: N)` and the same for dash.

- [ ] **Step 7: See `harness-cleans-workdir` red against a broken harness**

Temporarily delete the line `trap cleanup EXIT` from `tests/run.sh`.
Run: `sh tests/run.sh harness-cleans-workdir`
Expected: `FAIL harness-cleans-workdir` with `left behind by a passing run: tmp dir/spur-tests.<pid>`.
Put the line back (right after `cleanup() { rm -rf "$workdir"; }`), then re-run: `ok`.

- [ ] **Step 8: shellcheck**

Run: `MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/mnt" -w /mnt koalaman/shellcheck-alpine:stable shellcheck -s sh spur tests/run.sh tests/lib.sh tests/common.sh tests/cases/*.sh`
Expected: no output. If shellcheck reports SC2154 for `$names`/`$count` in `tests/run.sh`, the file-wide directive in the header is not being applied: make sure it is the last line of the header comment block and is followed by a blank line, as in `tests/lib.sh`.

- [ ] **Step 9: Commit**

```bash
git add tests/common.sh tests/run.sh tests/lib.sh tests/cases/harness-parallel-keeps-order.sh tests/cases/harness-failure-reported.sh tests/cases/harness-jobs-invalid.sh tests/cases/harness-cleans-workdir.sh tests/cases/harness-case-stdin-closed.sh
git commit -m "test(harness): run the cases in parallel workers

The harness selects the cases first (tests/common.sh), runs them in
SPUR_TEST_JOBS round-robin workers with stdin closed, then reports in
alphabetical order from one status file per case.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Stop the workers on Ctrl-C or TERM

**Files:**
- Modify: `tests/run.sh` (the traps and `run_worker`)
- Test: `tests/cases/harness-interrupt-stops-workers.sh` (new)

**Interfaces:**
- Consumes: `run_worker`, `workdir`, `fake_suite`, `capture`.
- Produces: `interrupt STATUS` in `tests/run.sh`; the stop marker `$workdir/.stop`.

- [ ] **Step 1: Write the failing case**

`tests/cases/harness-interrupt-stops-workers.sh`:

```sh
# A TERM mid-run stops the harness cleanly: the case in progress finishes, no
# other case starts, the work directory is removed, and the exit status is
# 143. INT goes through the same code (exit 130) but cannot be sent from
# here: a shell started in the background ignores SIGINT.
# $shell_under_test comes from tests/run.sh; $status is read by assert_status
# in tests/lib.sh.
# shellcheck disable=SC2154,SC2034
fake_suite
cat >fake/tests/cases/a-slow.sh <<'EOF'
: >"$FLAGS/a-started"
sleep 3
EOF
cat >fake/tests/cases/b-next.sh <<'EOF'
: >"$FLAGS/b-started"
EOF
mkdir flags tmp

FLAGS=$PWD/flags SPUR_TEST_TMPDIR=$PWD/tmp SPUR_TEST_JOBS=1 \
  "$shell_under_test" fake/tests/run.sh >stdout 2>stderr &
pid=$!
tries=0
until [ -f flags/a-started ]; do
  tries=$((tries + 1))
  if [ "$tries" -gt 20 ]; then
    kill "$pid"
    fail "a-slow never started"
  fi
  sleep 1
done
kill -TERM "$pid"
wait "$pid"
status=$?

assert_status 143
if [ -f flags/b-started ]; then fail "a case started after the TERM"; fi
if [ -s stdout ]; then fail "an interrupted run printed a report"; fi
set -- tmp/*
if [ -e "$1" ]; then fail "work directory left behind: $1"; fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `sh tests/run.sh harness-interrupt-stops-workers` and `SPUR_TEST_SHELL=dash sh tests/run.sh harness-interrupt-stops-workers`
Expected: `FAIL` — under dash, `work directory left behind` (no EXIT trap on death by signal); under bash, `a case started after the TERM` (the orphaned worker keeps going). Either failure is the right one.

- [ ] **Step 3: Implement the interrupt**

In `tests/run.sh`, replace

```sh
# shellcheck disable=SC2317,SC2329  # invoked through the EXIT and INT traps
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT

mkdir -p "$workdir" || {
  printf 'cannot create %s\n' "$workdir" >&2
  exit 70
}
```

with

```sh
# shellcheck disable=SC2317,SC2329  # invoked through the EXIT trap
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

mkdir -p "$workdir" || {
  printf 'cannot create %s\n' "$workdir" >&2
  exit 70
}

# interrupt STATUS -- let each worker finish the case it is running and start
# no other, wait for them, then exit with STATUS; the EXIT trap removes the
# work directory. Workers are asynchronous lists, which ignore SIGINT in a
# non-interactive shell, so a Ctrl-C reaches only this process and the stop
# has to be passed on. A second Ctrl-C stops waiting.
# shellcheck disable=SC2317,SC2329  # invoked through the INT and TERM traps
interrupt() {
  trap 'exit 130' INT
  : >"$workdir/.stop"
  wait
  exit "$1"
}
trap 'interrupt 130' INT
trap 'interrupt 143' TERM
```

and in `run_worker`, make the loop check the marker before each case:

```sh
  for name in $names; do
    [ ! -f "$workdir/.stop" ] || return 0
    if [ $((i % workers)) -eq "$1" ]; then
```

- [ ] **Step 4: Run it under sh, dash and bash, then the whole suite**

Run: `for s in sh dash bash; do SPUR_TEST_SHELL=$s sh tests/run.sh harness-interrupt-stops-workers; done`
Expected: `ok` three times.
Run: `SPUR_TEST_SHELL=dash sh tests/run.sh`
Expected: `88 passed, 0 failed`.

- [ ] **Step 5: Try a real Ctrl-C by hand**

Run `sh tests/run.sh` in an interactive Git Bash terminal and press Ctrl-C after a second or two.
Expected: the prompt returns within a few seconds, `echo $?` prints `130`, and `ls /tmp | grep spur-tests` prints nothing.

- [ ] **Step 6: shellcheck and commit**

Run the Task 2 shellcheck command. Expected: no output.

```bash
git add tests/run.sh tests/cases/harness-interrupt-stops-workers.sh
git commit -m "test(harness): stop the workers cleanly on Ctrl-C or TERM

Workers ignore SIGINT, so the trap leaves a stop marker they check before
each case, waits for them, and lets the EXIT trap clean up.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Per-case timings (`SPUR_TEST_TIMES`)

**Files:**
- Modify: `tests/common.sh` (append the clock), `tests/run.sh` (controls, `run_case`, report)
- Test (new): `tests/cases/harness-times.sh`, `tests/cases/harness-times-without-clock.sh`

**Interfaces:**
- Consumes: `run_case`, the report loop, `fake_suite`, `capture`.
- Produces (in `tests/common.sh`, used by Task 5):
  - `detect_clock` — sets `$clock` to `1` when `date +%s%N` prints ≥ 19 digits, else empty.
  - `now_ms` — sets `$ms` to the current time in milliseconds (call only when `$clock` is set).

- [ ] **Step 1: Write the two failing cases**

`tests/cases/harness-times.sh`:

```sh
# With SPUR_TEST_TIMES=1 each report line ends with the case's duration and
# the five slowest are listed after the summary. Where date has no
# sub-second clock the harness says so on stderr and carries on without
# timings; both outcomes are accepted, as in trace-flag.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
cat >fake/tests/cases/a-one.sh <<'EOF'
# The harness's own controls do not reach the cases.
if [ -n "${SPUR_TEST_TIMES+set}" ]; then echo "SPUR_TEST_TIMES leaked"; exit 1; fi
if [ -n "${SPUR_TEST_JOBS+set}" ]; then echo "SPUR_TEST_JOBS leaked"; exit 1; fi
EOF
printf ':\n' >fake/tests/cases/b-two.sh

capture env SPUR_TEST_TIMES=1 SPUR_TEST_JOBS=2 "$shell_under_test" fake/tests/run.sh
assert_status 0
case $stderr in
  *'timings unavailable'*)
    assert_stdout_has 'ok   a-one'
    assert_stdout_lacks ' ms)'
    ;;
  *)
    assert_stdout_matches '^ok   a-one  \([0-9]+ ms\)$'
    assert_stdout_matches '^ok   b-two  \([0-9]+ ms\)$'
    assert_stdout_has "2 passed, 0 failed (shell: $shell_under_test, jobs: 2)"
    assert_stdout_has 'slowest:'
    assert_stdout_matches '^ +[0-9]+ ms  a-one$'
    assert_stdout_matches '^ +[0-9]+ ms  b-two$'
    ;;
esac
```

`tests/cases/harness-times-without-clock.sh`:

```sh
# A date whose %N prints nothing, like busybox in Alpine, leaves whole
# seconds that look like a number. That is not a clock: the harness reports
# timings unavailable and runs without them.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf ':\n' >fake/tests/cases/a-one.sh
mkdir bin
printf '#!/bin/sh\necho 1790332364\n' >bin/date
chmod +x bin/date

capture env PATH="$PWD/bin:$PATH" SPUR_TEST_TIMES=1 "$shell_under_test" fake/tests/run.sh
assert_status 0
assert_stderr_has 'timings unavailable'
assert_stdout_is <<EOF
ok   a-one

1 passed, 0 failed (shell: $shell_under_test, jobs: 1)
EOF
```

- [ ] **Step 2: Run them to verify they fail**

Run: `sh tests/run.sh harness-times`
Expected: `FAIL harness-times` with `expected exit status 0, got 1`, and the captured stdout showing `FAIL a-one` / `SPUR_TEST_TIMES leaked` (the current harness does not unset it); and `FAIL harness-times-without-clock` with `stderr does not contain: timings unavailable`.

- [ ] **Step 3: Append the clock to `tests/common.sh`**

Change the file's directive line to

```sh
# shellcheck disable=SC2034  # $names, $count, $clock and $ms are read by the harnesses
```

and append:

```sh

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
```

- [ ] **Step 4: Wire timing into `tests/run.sh`**

(a) In the header, add to the Environment list and widen the directive:

```sh
#   SPUR_TEST_TIMES     1 adds each case's duration and lists the five slowest
# shellcheck disable=SC2154  # $names, $count, $clock and $ms come from tests/common.sh
```

(b) Right after the `SPUR_TEST_JOBS` block, add:

```sh
timing=
if [ "${SPUR_TEST_TIMES:-}" = 1 ]; then
  detect_clock
  if [ -n "$clock" ]; then
    timing=1
  else
    printf 'timings unavailable: date +%%s%%N does not print nanoseconds here\n' >&2
  fi
fi
```

(c) Add `SPUR_TEST_TIMES` to the `unset` line:

```sh
unset SPUR_BIN SPUR_ROOT SPUR_INVOCATION_DIR SPUR_TASK SPUR_STACK \
  SPUR_TEST_JOBS SPUR_TEST_TIMES
```

(d) Replace `run_case` with:

```sh
# run_case NAME -- run one case, leaving its output in NAME.log and, in
# NAME.status, its exit status followed by its duration in milliseconds when
# timing is on.
run_case() {
  mkdir "$workdir/$1"
  if [ -n "$timing" ]; then
    now_ms
    start=$ms
  fi
  (
    cd "$workdir/$1" || exit 1
    . "$root/tests/lib.sh"
    # shellcheck source=/dev/null
    . "$root/tests/cases/$1.sh"
  ) >"$workdir/$1.log" 2>&1 </dev/null
  rc=$?
  elapsed=
  if [ -n "$timing" ]; then
    now_ms
    elapsed=$((ms - start))
  fi
  printf '%s %s\n' "$rc" "$elapsed" >"$workdir/$1.status"
}
```

(e) Replace everything from `passed=0` to the end of the file with:

```sh
passed=0
failed=0
slowest=
# Case names are file names: no spaces, no glob characters.
# shellcheck disable=SC2086
for name in $names; do
  rc=
  elapsed=
  if [ -f "$workdir/$name.status" ]; then
    read -r rc elapsed <"$workdir/$name.status"
  fi
  suffix=${elapsed:+  ($elapsed ms)}
  if [ "$rc" = 0 ]; then
    passed=$((passed + 1))
    printf 'ok   %s%s\n' "$name" "$suffix"
  else
    failed=$((failed + 1))
    printf 'FAIL %s%s\n' "$name" "$suffix"
    sed 's/^/     /' "$workdir/$name.log"
  fi
  if [ -n "$elapsed" ]; then
    slowest="$slowest$elapsed $name
"
  fi
done

printf '\n%s passed, %s failed (shell: %s, jobs: %s)\n' \
  "$passed" "$failed" "$shell_under_test" "$workers"
if [ -n "$timing" ]; then
  printf '\nslowest:\n'
  printf '%s' "$slowest" | sort -rn | sed 5q | while read -r t n; do
    printf '%8s ms  %s\n' "$t" "$n"
  done
fi
if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
```

- [ ] **Step 5: Run the cases and the suite with and without timings**

Run: `sh tests/run.sh harness-times && SPUR_TEST_SHELL=dash sh tests/run.sh harness-times`
Expected: both cases `ok`, twice.
Run: `SPUR_TEST_TIMES=1 SPUR_TEST_SHELL=dash sh tests/run.sh`
Expected: every line ends with `  (N ms)`, `90 passed, 0 failed`, then `slowest:` and five lines. In particular `harness-parallel-keeps-order` stays `ok` (the outer `SPUR_TEST_TIMES` does not reach the nested harness).

- [ ] **Step 6: shellcheck and commit**

Run the Task 2 shellcheck command. Expected: no output.

```bash
git add tests/common.sh tests/run.sh tests/cases/harness-times.sh tests/cases/harness-times-without-clock.sh
git commit -m "test(harness): time each case with SPUR_TEST_TIMES=1

Each line gains its duration and the five slowest follow the summary. A
date without nanoseconds (busybox in Alpine prints whole seconds for
+%s%N) is detected and the run goes on without timings.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Benchmark harness (`tests/bench/`)

**Files:**
- Create: `tests/bench/run.sh`, `tests/bench/run-trivial.sh`, `tests/bench/list-500-tasks.sh`, `tests/bench/run-last-of-500.sh`, `tests/bench/check-50-tasks.sh`, `tests/bench/chain-depth-5.sh`, `tests/bench/discovery-deep.sh`
- Modify: `tests/lib.sh` (`fake_suite` also copies `tests/bench/run.sh`)
- Test (new): `tests/cases/harness-bench-failing-scenario.sh`, `harness-bench-no-match.sh`, `harness-bench-iterations-invalid.sh`, `harness-bench-without-clock.sh`

**Interfaces:**
- Consumes: `select_names DIR FILTER EXCLUDE`, `detect_clock`, `now_ms` (Tasks 2, 4); `capture`, `fake_suite`.
- Produces: `sh tests/bench/run.sh [name]`; inside a scenario, `measure ARGS...`, `$runner`, `$shell_under_test`, `$iterations`. Exit codes: 0 all ran, 1 a scenario failed, 64 usage, 69 no clock, 70 cannot create the work dir.

- [ ] **Step 1: Extend `fake_suite`**

In `tests/lib.sh`, add a last line to `fake_suite`:

```sh
  cp "$root/tests/bench/run.sh" fake/tests/bench/
```

- [ ] **Step 2: Write the four failing cases**

`tests/cases/harness-bench-failing-scenario.sh`:

```sh
# A scenario whose command fails, or that never measures, fails the benchmark
# harness (exit 1) while the others still print their numbers, and the work
# directory is removed. Without a sub-second clock nothing runs (exit 69).
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
cat >fake/tests/bench/good.sh <<'EOF'
printf 'hello:\n  echo hello\n' >Spurfile
measure hello
EOF
cat >fake/tests/bench/bad.sh <<'EOF'
printf 'hello:\n  echo hello\n' >Spurfile
measure no-such-task
EOF
cat >fake/tests/bench/lazy.sh <<'EOF'
printf 'hello:\n  echo hello\n' >Spurfile
EOF
mkdir tmp

capture env SPUR_BENCH_ITERATIONS=2 SPUR_TEST_TMPDIR="$PWD/tmp" \
  "$shell_under_test" fake/tests/bench/run.sh
case $stderr in
  *'no sub-second clock'*)
    assert_status 69
    ;;
  *)
    assert_status 1
    assert_stdout_has 'FAIL bad'
    assert_stdout_has 'measure no-such-task: exited 67'
    assert_stdout_has 'spur: unknown task: no-such-task'
    assert_stdout_has 'FAIL lazy'
    assert_stdout_has 'the scenario never called measure'
    assert_stdout_matches '^good +2 runs   min +[0-9]+ ms   mean +[0-9]+ ms   max +[0-9]+ ms$'
    assert_stdout_has "shell: $shell_under_test, iterations: 2"
    ;;
esac
set -- tmp/*
if [ -e "$1" ]; then fail "work directory left behind: $1"; fi
```

`tests/cases/harness-bench-no-match.sh`:

```sh
# The benchmark harness selects scenarios like the behavior harness selects
# cases, and selecting nothing is a usage error. Its own run.sh is not a
# scenario, not even by its exact name.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf 'measure --version\n' >fake/tests/bench/only.sh

capture "$shell_under_test" fake/tests/bench/run.sh nothing
assert_status 64
assert_stderr_has 'no benchmark matches: nothing'
assert_stdout_lacks 'only'

capture "$shell_under_test" fake/tests/bench/run.sh run
assert_status 64
assert_stderr_has 'no benchmark matches: run'
```

`tests/cases/harness-bench-iterations-invalid.sh`:

```sh
# SPUR_BENCH_ITERATIONS must be a positive integer; anything else is a usage
# error before any scenario runs.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf 'measure --version\n' >fake/tests/bench/only.sh

for n in 0 abc -1 07; do
  capture env SPUR_BENCH_ITERATIONS="$n" "$shell_under_test" fake/tests/bench/run.sh
  assert_status 64
  assert_stderr_has "SPUR_BENCH_ITERATIONS must be a positive integer, got: $n"
  assert_stdout_lacks 'only'
done
```

`tests/cases/harness-bench-without-clock.sh`:

```sh
# Without a sub-second clock the benchmark harness refuses to print numbers:
# it exits 69 with a message and runs nothing. The fake date prints whole
# seconds, as busybox in Alpine does for +%s%N.
# $shell_under_test comes from tests/run.sh.
# shellcheck disable=SC2154
fake_suite
printf 'measure --version\n' >fake/tests/bench/only.sh
mkdir bin
printf '#!/bin/sh\necho 1790332364\n' >bin/date
chmod +x bin/date

capture env PATH="$PWD/bin:$PATH" "$shell_under_test" fake/tests/bench/run.sh
assert_status 69
assert_stderr_has 'no sub-second clock'
assert_stdout_lacks 'only'
```

- [ ] **Step 3: Run them to verify they fail**

Run: `sh tests/run.sh harness-bench-`
Expected: all four `FAIL`, each log starting with `cp: cannot stat '.../tests/bench/run.sh'` (the harness does not exist yet).

- [ ] **Step 4: Create `tests/bench/run.sh`**

```sh
#!/bin/sh
# Benchmarks for spur.
#
# Usage:
#   sh tests/bench/run.sh [name]
#
# Selects scenarios in tests/bench/ the way tests/run.sh selects cases: an
# exact name, otherwise a substring filter; selecting nothing exits 64.
# Scenarios run one at a time, never in parallel, so they do not disturb
# each other's numbers. The output is numbers only: no baseline, no
# comparison, no threshold.
#
# A scenario is a straight-line script, run in its own temporary directory
# with $runner and $shell_under_test set. It prepares what it needs, then
# calls measure once:
#
#   measure ARGS...   run the runner with ARGS, output discarded: one warm-up
#                     run, then SPUR_BENCH_ITERATIONS timed runs. A failing
#                     run fails the scenario, since timing a broken command
#                     means nothing.
#
# Each timed run includes one call to date, the clock, so every number
# carries the same small overhead.
#
# Environment:
#   SPUR_TEST_SHELL        shell used to run the runner (default: sh)
#   SPUR_TEST_TMPDIR       where the scenario directories go (default: /tmp)
#   SPUR_BENCH_ITERATIONS  timed runs per scenario (default: 10)
#
# Exit status: 0 every scenario ran, 1 one failed, 64 usage error, 69 no
# sub-second clock, 70 the work directory could not be created.
# shellcheck disable=SC2154  # $names, $count, $clock and $ms come from tests/common.sh

case $0 in
  */*) here=${0%/*} ;;
  *) here=. ;;
esac
root=$(cd "$here/../.." && pwd)
runner=$root/spur
shell_under_test=${SPUR_TEST_SHELL:-sh}
filter=${1:-}
workdir=${SPUR_TEST_TMPDIR:-/tmp}/spur-bench.$$

# shellcheck source=tests/common.sh
. "$root/tests/common.sh"

# A positive integer; leading zeros are refused, as for SPUR_TEST_JOBS.
iterations=${SPUR_BENCH_ITERATIONS:-10}
case $iterations in
  *[!0-9]* | 0*)
    printf 'SPUR_BENCH_ITERATIONS must be a positive integer, got: %s\n' "$iterations" >&2
    exit 64
    ;;
esac

unset SPUR_BIN SPUR_ROOT SPUR_INVOCATION_DIR SPUR_TASK SPUR_STACK

# This file sits among the scenarios but is not one.
select_names "$root/tests/bench" "$filter" run
if [ "$count" -eq 0 ]; then
  printf 'no benchmark matches: %s\n' "$filter" >&2
  exit 64
fi

detect_clock
if [ -z "$clock" ]; then
  printf 'no sub-second clock: date +%%s%%N does not print nanoseconds here\n' >&2
  exit 69
fi

# shellcheck disable=SC2317,SC2329  # invoked through the EXIT trap
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$workdir" || {
  printf 'cannot create %s\n' "$workdir" >&2
  exit 70
}

# measure_failed STATUS ARGS... -- end the scenario after a failing run,
# showing what the runner printed on stderr.
measure_failed() {
  code=$1
  shift
  printf 'measure %s: exited %s\n' "$*" "$code"
  cat "$bench_errors"
  exit 1
}

# measure ARGS... -- time the runner with ARGS: one warm-up run, then
# $iterations timed runs. Leaves "RUNS MIN MEAN MAX" in the scenario's
# result file.
measure() {
  if [ -f "$bench_result" ]; then
    printf 'measure called twice: one measurement per scenario\n'
    exit 1
  fi
  "$shell_under_test" "$runner" "$@" >/dev/null 2>"$bench_errors" ||
    measure_failed "$?" "$@"
  n=0
  min=
  max=0
  sum=0
  while [ "$n" -lt "$iterations" ]; do
    now_ms
    start=$ms
    "$shell_under_test" "$runner" "$@" >/dev/null 2>"$bench_errors" ||
      measure_failed "$?" "$@"
    now_ms
    t=$((ms - start))
    if [ -z "$min" ] || [ "$t" -lt "$min" ]; then min=$t; fi
    if [ "$t" -gt "$max" ]; then max=$t; fi
    sum=$((sum + t))
    n=$((n + 1))
  done
  printf '%s %s %s %s\n' "$n" "$min" "$((sum / n))" "$max" >"$bench_result"
}

width=0
# Scenario names are file names: no spaces, no glob characters.
# shellcheck disable=SC2086
for name in $names; do
  [ "${#name}" -le "$width" ] || width=${#name}
done

failed=0
# shellcheck disable=SC2086
for name in $names; do
  bench_result=$workdir/$name.result
  bench_errors=$workdir/$name.errors
  mkdir "$workdir/$name"
  if (
    cd "$workdir/$name" || exit 1
    # shellcheck source=/dev/null
    . "$root/tests/bench/$name.sh"
    if [ ! -f "$bench_result" ]; then
      printf 'the scenario never called measure\n'
      exit 1
    fi
  ) >"$workdir/$name.log" 2>&1 </dev/null; then
    read -r runs min mean max <"$bench_result"
    label=$name
    while [ "${#label}" -lt "$width" ]; do label="$label "; done
    printf '%s  %3s runs   min %5s ms   mean %5s ms   max %5s ms\n' \
      "$label" "$runs" "$min" "$mean" "$max"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$name"
    sed 's/^/     /' "$workdir/$name.log"
  fi
done

printf '\nshell: %s, iterations: %s\n' "$shell_under_test" "$iterations"
if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
```

- [ ] **Step 5: Run the four cases**

Run: `sh tests/run.sh harness-bench- && SPUR_TEST_SHELL=dash sh tests/run.sh harness-bench-`
Expected: four `ok`, twice.

- [ ] **Step 6: Create the six scenarios**

`tests/bench/run-trivial.sh`:

```sh
# The baseline: end-to-end latency of a task that only echoes.
printf 'hello:\n  echo hello\n' >Spurfile
measure hello
```

`tests/bench/list-500-tasks.sh`:

```sh
# Parser scaling in list mode: 500 tasks with a description each.
i=0
while [ "$i" -lt 500 ]; do
  printf 'task-%s: ## t\n  echo %s\n' "$i" "$i"
  i=$((i + 1))
done >Spurfile
measure --list
```

`tests/bench/run-last-of-500.sh`:

```sh
# Body extraction from a large Spurfile: the task is the last of 500.
i=0
while [ "$i" -lt 500 ]; do
  printf 'task-%s: ## t\n  echo %s\n' "$i" "$i"
  i=$((i + 1))
done >Spurfile
measure task-499
```

`tests/bench/check-50-tasks.sh`:

```sh
# The cost of --check, which assembles and parses every task: three processes
# per task, so 50 tasks rather than 500 (500 take minutes per run).
i=0
while [ "$i" -lt 50 ]; do
  printf 'task-%s: ## t\n  echo %s\n' "$i" "$i"
  i=$((i + 1))
done >Spurfile
measure --check
```

`tests/bench/chain-depth-5.sh`:

```sh
# spur calling spur: five runner starts, each task calling the next.
cat >Spurfile <<'EOF'
l1:
  spur l2
l2:
  spur l3
l3:
  spur l4
l4:
  spur l5
l5:
  echo bottom
EOF
measure l1
```

`tests/bench/discovery-deep.sh`:

```sh
# The upward search: the Spurfile is ten directories above the caller.
printf 'hello:\n  echo hello\n' >Spurfile
mkdir -p a/b/c/d/e/f/g/h/i/j
cd a/b/c/d/e/f/g/h/i/j || exit 1
measure hello
```

- [ ] **Step 7: Run every scenario once**

Run: `SPUR_BENCH_ITERATIONS=1 SPUR_TEST_SHELL=dash sh tests/bench/run.sh`
Expected: six lines, alphabetical (`chain-depth-5`, `check-50-tasks`, `discovery-deep`, `list-500-tasks`, `run-last-of-500`, `run-trivial`), each `  1 runs   min … ms   mean … ms   max … ms`, then `shell: dash, iterations: 1`, exit 0.
Run: `sh tests/bench/run.sh run-`
Expected: only `run-last-of-500` and `run-trivial`.

- [ ] **Step 8: Whole suite, shellcheck, commit**

Run: `SPUR_TEST_SHELL=dash sh tests/run.sh` — expected `94 passed, 0 failed`.
Run: `MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/mnt" -w /mnt koalaman/shellcheck-alpine:stable shellcheck -s sh spur tests/run.sh tests/lib.sh tests/common.sh tests/bench/*.sh tests/cases/*.sh` — expected no output.

```bash
git add tests/lib.sh tests/bench tests/cases/harness-bench-failing-scenario.sh tests/cases/harness-bench-no-match.sh tests/cases/harness-bench-iterations-invalid.sh tests/cases/harness-bench-without-clock.sh
git commit -m "test(bench): add a benchmark harness and six scenarios

sh tests/bench/run.sh runs the scenarios one at a time and prints min,
mean and max per scenario, numbers only. One scenario per runner stage.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `exec-minimal-path` and the runner's dependency statement

**Files:**
- Test: `tests/cases/exec-minimal-path.sh` (new)
- Modify: `README.md:56-57`, `README.md:159`, `AGENTS.md:112`, `CONTRIBUTING.md:56`

**Interfaces:**
- Consumes: `capture`, `spurfile`, `assert_*`.
- Produces: nothing used later.

- [ ] **Step 1: Write the case**

`tests/cases/exec-minimal-path.sh`:

```sh
# The runner needs sh, awk, dirname, basename and cat (for --help), and
# nothing else: every path through it works with only those on PATH.
# $runner and $shell_under_test come from tests/run.sh.
# shellcheck disable=SC2154
spurfile <<'EOF'
greet: ## say hello
  echo "hello $1"

outer:
  spur greet world
EOF

# Each tool is a script that execs the real one by its absolute path. A copy
# or a symlink would do on Linux, but not under MSYS (Git Bash), where a
# copied binary no longer finds the DLLs that sit next to the original.
mkdir bin
for tool in sh awk dirname basename cat; do
  real=$(command -v "$tool") || fail "no $tool on PATH"
  # shellcheck disable=SC2016  # "$@" is for the wrapper, not expanded here
  printf '#!/bin/sh\nexec '\''%s'\'' "$@"\n' "$real" >"bin/$tool"
  chmod +x "bin/$tool"
done
shell=$(command -v "$shell_under_test") || fail "cannot resolve $shell_under_test"

minimal() { capture env PATH="$PWD/bin" "$shell" "$runner" "$@"; }

minimal --list
assert_status 0
assert_stdout_has 'say hello'

minimal --help
assert_status 0
assert_stdout_has 'Usage:'

minimal greet you
assert_status 0
assert_stdout_is <<'EOF'
hello you
EOF

minimal --check
assert_status 0

# spur called from a task: the child runner sees the same PATH.
minimal outer
assert_status 0
assert_stdout_is <<'EOF'
hello world
EOF

# Negative control: without awk the runner cannot parse, which proves the
# restricted PATH is the only one it sees.
rm bin/awk
minimal --list
assert_status 127
```

- [ ] **Step 2: Run it under sh, dash and bash**

Run: `for s in sh dash bash; do SPUR_TEST_SHELL=$s sh tests/run.sh exec-minimal-path; done`
Expected: `ok` three times (the runner already meets the diet).

- [ ] **Step 3: See it red against a deliberately broken runner**

In `spur`, inside `usage()`, temporarily change `cat <<EOF` to `sed -n p <<EOF`.
Run: `sh tests/run.sh exec-minimal-path`
Expected: `FAIL exec-minimal-path` with `stdout does not contain: Usage:` (`sed` is not on the restricted PATH).
Restore: `git checkout -- spur`, re-run, expect `ok`.

- [ ] **Step 4: Update the dependency statement**

`README.md` lines 56–57, replace

```markdown
- **Nothing to install.** The runner is one file that depends on `sh` and
`awk`. Fetch it with `curl`, or commit it into the repository and let
```

with

```markdown
- **Nothing to install.** The runner is one file that depends on `sh`, `awk`
and the basic POSIX utilities `dirname`, `basename` and `cat`, nothing else (a
test runs it with only those on `PATH`). Fetch it with `curl`, or commit it
into the repository and let
```

`README.md` line 159, replace

```markdown
The runner is one file with no dependencies beyond `sh` and `awk`, so
```

with

```markdown
The runner is one file with no dependencies beyond `sh`, `awk` and the basic
POSIX utilities `dirname`, `basename` and `cat`, so
```

(Leave the comparison table's `none: \`sh\` and \`awk\`` as is: it answers "runtime to install", and the three utilities are part of every POSIX system.)

`AGENTS.md` lines 112–113, replace

```markdown
- The runner may depend on `sh` and `awk` only. No `mktemp`, no `stat`, no
  temporary files.
```

with

```markdown
- The runner may depend on `sh`, `awk` and the basic POSIX utilities
  `dirname`, `basename` and `cat`, nothing else; `exec-minimal-path` holds it
  to that. No `mktemp`, no `stat`, no temporary files.
```

`CONTRIBUTING.md` lines 56–57, replace

```markdown
- The runner depends on `sh` and `awk` only. No `mktemp`, no `stat`, no
  temporary files.
```

with

```markdown
- The runner depends on `sh`, `awk` and the basic POSIX utilities `dirname`,
  `basename` and `cat`, nothing else; `exec-minimal-path` holds it to that.
  No `mktemp`, no `stat`, no temporary files.
```

- [ ] **Step 5: shellcheck and commit**

Run the Task 5 shellcheck command. Expected: no output.

```bash
git add tests/cases/exec-minimal-path.sh README.md AGENTS.md CONTRIBUTING.md
git commit -m "test: pin the runner's dependencies with exec-minimal-path

The runner runs with only sh, awk, dirname, basename and cat on PATH, and
the documents now say so.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Documentation, Spurfile, CI, skill

**Files:**
- Modify: `AGENTS.md` (Commands, CI paragraph, Test suite), `CONTRIBUTING.md` (Running the tests, Writing a case, new Benchmarks section), `Spurfile`, `.github/workflows/ci.yml`, `.claude/skills/spur-tests/SKILL.md`, `.claude/skills/spur-tests/references/coverage-map.md`

**Interfaces:**
- Consumes: every name produced by Tasks 1–6.
- Produces: nothing used later.

- [ ] **Step 1: Spurfile**

Replace the top of the file down to `test-all:` so it reads:

```sh
# Spurfile for spur itself. If these tasks are uncomfortable to write, the
# design is wrong and we find out in the first week.
HARNESS=tests/run.sh
BENCH=tests/bench/run.sh
SOURCES="spur tests/run.sh tests/lib.sh tests/common.sh tests/bench/*.sh"

## Arguments go to the harness: a case name runs just that case, and a name
## no case has runs every case containing it.
##   spur test discovery-flag-f
##   spur test parse-
test: ## run the behavior tests
  sh "$HARNESS" "$@"

## Arguments go to the benchmark harness, selected like test. Set
## SPUR_BENCH_ITERATIONS for more or fewer timed runs (default 10).
##   spur bench run-
bench: ## measure the runner's performance
  sh "$BENCH" "$@"
```

(`test-all`, `lint`, `check` stay as they are; `lint` picks up the new files through `$SOURCES`, whose `tests/bench/*.sh` expands unquoted in `shellcheck -s sh $SOURCES tests/cases/*.sh`.)

Verify: `./spur --check && ./spur --list` — expected: no output from `--check`, and `bench` listed with `measure the runner's performance`. Then `./spur bench run-trivial` with `SPUR_BENCH_ITERATIONS=2` — expected one numbers line.

- [ ] **Step 2: CI**

In `.github/workflows/ci.yml`, change the lint step to:

```yaml
      - name: Lint
        run: shellcheck -s sh spur tests/run.sh tests/lib.sh tests/common.sh tests/bench/*.sh tests/cases/*.sh
```

and append a job after `busybox`:

```yaml

  bench:
    name: bench smoke
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dash
        run: sudo apt-get update && sudo apt-get install -y dash
      - name: Run every scenario once
        # Keeps the scenarios from rotting; the numbers are not checked.
        run: SPUR_BENCH_ITERATIONS=1 SPUR_TEST_SHELL=dash sh tests/bench/run.sh
```

- [ ] **Step 3: AGENTS.md**

Replace the Commands code block with:

```sh
sh tests/run.sh                        # full behavior suite, in parallel
sh tests/run.sh discovery-flag-f       # a single case, by its exact name
sh tests/run.sh parse-                 # no case has that name: every case containing it (a group)
SPUR_TEST_SHELL=dash sh tests/run.sh   # strictest shell; if it passes here it is POSIX
SPUR_TEST_JOBS=1 sh tests/run.sh       # one case at a time
SPUR_TEST_TIMES=1 sh tests/run.sh      # each case's duration, and the five slowest
sh tests/bench/run.sh [name]           # benchmarks: numbers only, no baseline
shellcheck -s sh spur tests/run.sh tests/lib.sh tests/common.sh tests/bench/*.sh tests/cases/*.sh
```

In the next paragraph, change `(`./spur test`, `./spur lint`, `./spur test-all`, `./spur check`)` to `(`./spur test`, `./spur bench`, `./spur lint`, `./spur test-all`, `./spur check`)`.

Replace the CI paragraph with:

```markdown
CI (`.github/workflows/ci.yml`) runs shellcheck plus the suite under `sh`,
`dash`, `bash` and busybox ash (Alpine in Docker), and runs every benchmark
scenario once so none rots. Nothing is skipped locally that CI will not
catch, but `dash` catches almost everything.
```

In `## Test suite`, replace the first two paragraphs (from "`tests/run.sh` is a hand-rolled harness" to "does not leak the outer invocation's state into cases.") with:

```markdown
`tests/run.sh` is a hand-rolled harness — no bats, no shellspec, deliberately:
a tool that advertises zero dependencies cannot need a framework to test
itself. It selects the cases (the rule lives in `tests/common.sh`, shared
with the benchmark harness), runs them in parallel workers (`SPUR_TEST_JOBS`,
default the number of CPUs), then reports in alphabetical order, so the
output does not depend on the number of workers. `SPUR_TEST_TIMES=1` adds
each case's duration and the five slowest. Each case runs in a subshell in
its own temp dir under `${SPUR_TEST_TMPDIR:-/tmp}`, with stdin closed and
`tests/lib.sh` sourced for helpers: `spurfile` (heredoc → `./Spurfile`),
`run ARGS...` (fills the files `stdout` and `stderr`, the variables `$stdout`
and `$stderr`, and `$status`), `capture CMD...` (the same for any other
command: the harness, a vendored copy of the runner), `assert_status`,
`assert_stdout_is` (byte-exact, heredoc),
`assert_{stdout,stderr}_{has,lacks,matches}`, `fail`, and `fake_suite` (a
copy of the harnesses and the runner in `./fake`, for `harness-` cases). The
`has`/`lacks` assertions read the variables, so a command run without `run`
or `capture` is invisible to them.

`run.sh` unsets the `SPUR_*` variables before the cases run, its own
`SPUR_TEST_JOBS` and `SPUR_TEST_TIMES` included, so running the suite through
`./spur test` does not leak the outer invocation's state into cases.

`tests/bench/run.sh` measures the runner. It selects scenarios in
`tests/bench/` by the same rule, runs them one at a time, and prints min,
mean and max per scenario: numbers only, no baseline, no threshold. A
scenario is a straight-line script, like a case, that prepares its directory
and calls `measure ARGS...` once: one warm-up run of the runner with ARGS,
then `SPUR_BENCH_ITERATIONS` (default 10) timed runs; a failing run fails the
scenario. It needs `date +%s%N` to print nanoseconds and exits 69 when it
does not.
```

In the next paragraph, replace "Cases run in alphabetical order and are independent of one another, so the order carries no meaning." with "Cases run in parallel and must be independent of one another; the report is alphabetical, and `SPUR_TEST_JOBS=1` runs them one at a time."

- [ ] **Step 4: CONTRIBUTING.md**

In `## Running the tests`, after the code block's existing three lines add:

```sh
SPUR_TEST_JOBS=1 sh tests/run.sh    # one case at a time (default: one worker per CPU)
SPUR_TEST_TIMES=1 sh tests/run.sh   # each case's duration, and the five slowest
```

and replace the paragraph "The harness has no dependencies: each case gets its own temporary directory under `/tmp` …" with:

```markdown
The harness has no dependencies: it runs the cases in parallel workers, each
in its own temporary directory under `/tmp` (override with
`SPUR_TEST_TMPDIR`) with stdin closed, and reports in alphabetical order once
they have all finished. A case writes a `Spurfile`, runs the runner, and
compares stdout, stderr and the exit status. Cases must not depend on one
another. `bats` and `shellspec` were both rejected: a tool that sells itself
as zero-dependency cannot require a framework to run its own tests.
```

In the helper table, change the `run` row and add three rows after it:

```markdown
| `run ARGS...` | runs the runner; fills the files `stdout` and `stderr`, the variables `$stdout` and `$stderr`, and `$status` |
| `capture CMD...` | the same for any command (the harness, a vendored copy of the runner) |
| `fake_suite` | copies the harnesses and the runner into `./fake`, with empty `tests/cases` and `tests/bench`; for `harness-` cases |
```

and under the table add:

```markdown
The `has`/`lacks` assertions read `$stdout` and `$stderr`, so run commands
through `run` or `capture`. A case ends with the status of its last command:
end it with `if [ ... ]; then fail ...; fi`, never with `[ ... ] && fail`.
```

Add a section before `## Rules`:

````markdown
## Benchmarks

```sh
sh tests/bench/run.sh              # or: ./spur bench
sh tests/bench/run.sh run-         # a filter, as for the tests
SPUR_BENCH_ITERATIONS=30 SPUR_TEST_SHELL=dash sh tests/bench/run.sh
```

The benchmark harness prints min, mean and max per scenario — numbers only,
with no baseline and no comparison; compare shells or revisions by hand. It
needs `date +%s%N` to print nanoseconds (GNU date does; macOS and busybox in
Alpine do not) and exits 69 otherwise.

A scenario is `tests/bench/<name>.sh`: a straight-line script that runs in
its own temporary directory, prepares what it needs, and calls
`measure ARGS...` once. `measure` runs the runner with ARGS once to warm up,
then `SPUR_BENCH_ITERATIONS` (default 10) timed times, output discarded; if
any run fails, the scenario fails with the runner's stderr.
````

- [ ] **Step 5: The `spur-tests` skill**

In `.claude/skills/spur-tests/SKILL.md`:

- In the pieces table, change the `tests/run.sh` row to `| \`tests/run.sh\` | The harness: picks cases, runs them in parallel workers, each in its own temp dir, and prints \`ok\` / \`FAIL\` in alphabetical order. |` and add rows `| \`tests/common.sh\` | Case selection and the clock, shared by both harnesses. |` and `| \`tests/bench/\` | The benchmark harness (\`run.sh\`) and its scenarios. |`.
- In "Two different dependency budgets", change "`grep`, `sed`, `diff`, `basename`, `mkdir`, `rm`" to "`grep`, `sed`, `diff`, `sort`, `mkdir`, `rm`", and append: "The runner's diet is pinned by `exec-minimal-path`, which runs it with only `sh`, `awk`, `dirname`, `basename` and `cat` on `PATH`."
- In "Running", add to the code block `SPUR_TEST_JOBS=1 sh tests/run.sh       # one case at a time` and `SPUR_TEST_TIMES=1 sh tests/run.sh      # durations, and the five slowest`.
- In "Writing a case", replace "Cases run in alphabetical order, each in its own directory, each in a subshell. Order carries no meaning and no case may depend on another." with "Cases run in parallel workers, each in its own directory, each in a subshell with stdin closed; the report is alphabetical, and `SPUR_TEST_JOBS=1` runs them one at a time. Order carries no meaning and no case may depend on another."
- Replace the section "When a case needs to bypass `run`" body with:

````markdown
Some cases must invoke something other than `run` — a vendored copy of the
runner through a relative path (`chain-call-relative-path`), or the harness
itself (`harness-selects-by-name`, and every case that uses `fake_suite`).
Those go through `capture CMD...`, which fills the same files and variables
as `run`. The `has`/`lacks` assertions read `$stdout` and `$stderr`, not the
files, so a command run by hand would leave them asserting on stale output.

The one exception is a pipe into the runner (`exec-stdin-is-free`): a
pipeline would run `capture` in a subshell and lose `$status`, so that case
sets `status=$?` by hand and asserts through files only. Such a case carries
a justified disable at the top:

```sh
# $runner and $shell_under_test come from tests/run.sh; $status is read by
# assert_status in tests/lib.sh.
# shellcheck disable=SC2154,SC2034
```

Every `# shellcheck disable=` in this repository explains itself on the line
above. Keep that habit; a bare disable is indistinguishable from a bug.

If a case starts the real harness again, it may only select cases that do
*not* themselves start a harness — otherwise the suite recurses. Cases that
need a harness to run arbitrary cases use `fake_suite` and write their own.
A case ends with its last command's status: finish with
`if [ ... ]; then fail ...; fi`, never with `[ ... ] && fail`.
````

- Add a section before "Proposing improvements":

```markdown
## Benchmarks

`sh tests/bench/run.sh [name]` times the runner, scenario by scenario, and
prints numbers only. A scenario is `tests/bench/<name>.sh`, a straight-line
script that prepares its directory and calls `measure ARGS...` once; `measure`
warms up, then runs the runner `SPUR_BENCH_ITERATIONS` times. Benchmarks
guide work on the runner's speed; they pin nothing, and a slow number is
never a failing test. They need `date +%s%N` in nanoseconds (not macOS, not
busybox in Alpine).
```

In `.claude/skills/spur-tests/references/coverage-map.md`:

- Replace the `harness-` paragraph with:

```markdown
**`harness-`** (14, refreshed 2026-09-25) — exact name beats substring,
substring selects a group, selecting nothing is 64
(`harness-selects-by-name`); `has`/`lacks` match literally, `capture` reloads
the output (`harness-helpers-literal-match`); parallel output is alphabetical
and identical to a serial run, with the workers proven to overlap
(`harness-parallel-keeps-order`); a failure prints its indented log and exits
1 (`harness-failure-reported`); `SPUR_TEST_JOBS` validation and cap
(`harness-jobs-invalid`); the work dir is removed on pass and fail, with a
space in its path (`harness-cleans-workdir`); stdin is closed
(`harness-case-stdin-closed`); TERM stops the workers and cleans up
(`harness-interrupt-stops-workers`); timings with a clock, the notice
without one, and no leak of the controls into cases (`harness-times`,
`harness-times-without-clock`); the benchmark harness fails on a failing or
measure-less scenario, refuses a bad filter, bad iterations and a missing
clock (`harness-bench-*`).
```

- In the `exec-` paragraph, change `(10)` to `(11)` and append: "the runner works with only `sh`, `awk`, `dirname`, `basename` and `cat` on `PATH` (`exec-minimal-path`)."
- In "Harness-level ideas", delete the "Stdin is inherited by every case" bullet (done: cases run with stdin closed) and the "Reporting which cases ran" bullet (superseded: the harness now runs in parallel and has timings; keep the report itself plain).

- [ ] **Step 6: Check the docs against the code, then commit**

Run: `grep -rn 'alphabetical order' AGENTS.md CONTRIBUTING.md .claude/skills/spur-tests/SKILL.md`
Expected: every hit describes the *report* order, none says cases *run* in alphabetical order.
Run: `SPUR_TEST_SHELL=dash sh tests/run.sh` — expected `95 passed, 0 failed`.

```bash
git add AGENTS.md CONTRIBUTING.md Spurfile .github/workflows/ci.yml .claude/skills/spur-tests
git commit -m "docs: document the parallel harness, timings and benchmarks

Adds the bench task, lints tests/common.sh and tests/bench/, and runs
every scenario once in CI.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Verification

**Files:** none modified (a fix found here goes back to the task that owns the file, as its own commit).

- [ ] **Step 1: The shell matrix**

Run: `for s in sh dash bash; do SPUR_TEST_SHELL=$s sh tests/run.sh | tail -n 1; done`
Expected: `95 passed, 0 failed (shell: <s>, jobs: N)` three times.
Run: `MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/work" -w /work alpine:3.20 sh -c "apk add --no-cache diffutils >/dev/null && sh tests/run.sh" | tail -n 1`
Expected: `95 passed, 0 failed (shell: sh, jobs: N)`.

- [ ] **Step 2: shellcheck, as CI runs it**

Run: `MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/mnt" -w /mnt koalaman/shellcheck-alpine:stable shellcheck -s sh spur tests/run.sh tests/lib.sh tests/common.sh tests/bench/*.sh tests/cases/*.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Wall time, before and after**

Run: `time sh tests/run.sh >/dev/null`
Expected: well under the Task 1 baseline. Report both numbers and the worker count.
Run: `SPUR_TEST_TIMES=1 sh tests/run.sh | tail -n 8` and report the five slowest.

- [ ] **Step 4: The benchmarks, once**

Run: `SPUR_TEST_SHELL=dash sh tests/bench/run.sh`
Expected: six numbers lines and `shell: dash, iterations: 10`, exit 0. Show the output as is.

- [ ] **Step 5: Line endings and a clean tree**

Run: `git ls-files --eol tests/ Spurfile | grep -v 'i/lf' ; git status --short`
Expected: no output from either.
