# Spur Task Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `spur`, a single-file task runner written in strict POSIX sh that reads a `Spurfile`, lists tasks, and runs each one in a single shell with positional argument passthrough.

**Architecture:** One executable sh script with an embedded awk program held in a single-quoted shell variable. The awk program is the parser: it validates the file, emits the task list, the preamble, or the dedented body of one task. The shell script assembles `prelude + preamble + body` into a string and hands it to `sh -c "$script" "spur <task>" "$@"`, which gives the task native `$0` and positional parameters, leaves stdin free, and needs no temporary file. There is no build step: the file in the repository is the file that gets installed.

**Tech Stack:** POSIX sh (dash, bash, busybox ash), POSIX awk, POSIX coreutils. Tests: a ~90-line sh harness, no framework. CI: GitHub Actions running `shellcheck -s sh` plus a shell matrix.

**Spec:** `docs/superpowers/specs/2026-09-21-spur-task-runner-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **English only, everywhere.** Source code, comments, error messages, `--help`
  text, `--list` output, README, CONTRIBUTING, LICENSE, the `Spurfile`, test
  names, test files, CI workflow, and commit messages. The repository is
  served to the consumer in English. The Portuguese design documents already
  committed under `docs/superpowers/` are translated in Task 10.
- **Strict POSIX sh.** No bashisms: no `[[ ]]`, no `local`, no arrays, no
  `${var,,}`, no `function` keyword, no `source`, no `echo -n`, no `+=`.
  `shellcheck -s sh` must pass clean.
- **Strict POSIX awk.** No `gensub`, no `asort`, no `delete array` (whole
  array), no `/dev/stderr`, no `length(array)`. Errors are reported on stdout
  and signalled by the awk exit status.
- **Runtime dependencies:** `sh` and `awk` only. No `mktemp`, no `stat`, no
  `realpath`, no `sed`/`grep` in the runner's hot path, no temporary files.
- **Single file.** The runner is exactly one file named `spur` at the
  repository root. The awk program lives inside it as a single-quoted string,
  so the awk source must never contain a single quote character.
- **Version:** `VERSION=0.1.0`.
- **Exit codes:** a task's exit code is propagated unchanged. Runner errors
  use 64 (usage), 65 (malformed Spurfile), 66 (Spurfile not found), 67
  (unknown task), 68 (recursion detected).
- **Error message format:** every runner diagnostic goes to stderr and starts
  with `spur: `.
- **Commit messages:** Conventional Commits in English, and every commit ends
  with the trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Run the tests with:** `sh tests/run.sh`. Under another shell:
  `SPUR_TEST_SHELL=dash sh tests/run.sh`.

## Spec Gaps Resolved Here

The design document leaves these undefined. They are decided here so the
implementation is deterministic; each one is covered by a test.

1. **Comments at column 0 after the first task.** Allowed. A line whose first
   character is `#` is a comment anywhere in the file, never a syntax error.
   Being content at column zero, it closes an open task body (grammar rule 5).
2. **Make-style prerequisites** (`build: deps`). Syntax error, code 65,
   message `task header takes no prerequisites: build`. Silently ignoring them
   would trap every user coming from make.
3. **Duplicate task names.** Syntax error, code 65. Always a bug, never intent.
4. **Bare `spur`** lists the tasks and exits 0, as the spec's CLI section says.
   `spur -n` or `spur -x` with no task name is a usage error (64): those flags
   only mean something for a task.
5. **`-C` pointing at a directory that does not exist** is a usage error (64).
   **`-f` pointing at a file that does not exist** is 66 (Spurfile not found).
6. **Dedent** removes the longest common leading-*whitespace prefix* (compared
   as a string), not a character count. This is correct when tabs and spaces
   are mixed, where counting is not.
7. **Trailing blank lines are trimmed** from a task body. Blank lines inside
   the body are preserved.
8. **Chained calls under `-f`.** The injected `spur` function runs
   `"$SPUR_BIN" "$@"`, so a nested call re-discovers the Spurfile by ascending
   search from `SPUR_ROOT` and does not inherit `-f`. Documented as a known
   limitation in the README rather than worked around, because propagating
   `-f` would break `spur -C sub build` inside a body.

## File Structure

| File | Responsibility |
|---|---|
| `spur` | The whole runner: argument parsing, Spurfile discovery, the embedded awk parser, script assembly, execution. ~250 lines. |
| `tests/run.sh` | Harness: iterates over case files, runs each in its own temporary directory, reports pass/fail. |
| `tests/lib.sh` | Assertion helpers sourced into each case. |
| `tests/cases/NNN-name.sh` | One behavior case each. Plain sh using the helpers. |
| `Spurfile` | Dogfooding: `test`, `test-all`, `lint`, `check`. |
| `README.md` | What it is, install, the Spurfile language, the CLI, limitations, Windows. |
| `CONTRIBUTING.md` | How to run the tests and the shell matrix locally. |
| `LICENSE` | MIT. |
| `.github/workflows/ci.yml` | shellcheck + shell matrix + busybox ash via Docker. |

The runner stays in one file on purpose: splitting `resolve.awk` out would
force the script to locate its own sibling through symlinks, a relative `$0`,
and `/usr/local/bin`. The test harness is split in two (`run.sh` + `lib.sh`)
because the helpers are sourced into a subshell per case, and a separate file
is what makes that sourcing clean.

---

### Task 1: Test harness and runner skeleton

**Files:**
- Create: `tests/run.sh`
- Create: `tests/lib.sh`
- Create: `tests/cases/010-version.sh`
- Create: `tests/cases/011-help.sh`
- Create: `tests/cases/012-unknown-option.sh`
- Create: `tests/cases/013-option-missing-argument.sh`
- Create: `spur`

**Interfaces:**
- Consumes: nothing.
- Produces: the harness contract every later task uses — a case file runs with
  its cwd set to a private temporary directory and these helpers in scope:
  `spurfile` (reads a heredoc from stdin and writes `./Spurfile`),
  `run ARGS...` (runs the runner, captures `./stdout`, `./stderr`, sets
  `$status`), `assert_status N`, `assert_stdout_is` (heredoc on stdin, exact
  match), `assert_stdout_has TEXT`, `assert_stdout_lacks TEXT`,
  `assert_stdout_matches ERE`, `assert_stderr_has TEXT`,
  `assert_stderr_lacks TEXT`, `assert_stderr_matches ERE`, `fail MESSAGE`.
  Also produces `spur`'s flag-parsing loop and the `die CODE MESSAGE` helper.

- [ ] **Step 1: Write the harness**

`tests/run.sh`:

```sh
#!/bin/sh
# Behavior tests for spur.
#
# Usage:
#   sh tests/run.sh [name-filter]
#
# Environment:
#   SPUR_TEST_SHELL     shell used to run the runner under test (default: sh)
#   SPUR_TEST_TMPDIR    where the per-case directories go (default: /tmp)

root=$(cd "$(dirname "$0")/.." && pwd)
runner=$root/spur
shell_under_test=${SPUR_TEST_SHELL:-sh}
filter=${1:-}
workdir=${SPUR_TEST_TMPDIR:-/tmp}/spur-tests.$$
passed=0
failed=0

cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT

mkdir -p "$workdir" || {
  printf 'cannot create %s\n' "$workdir" >&2
  exit 70
}

for case_file in "$root"/tests/cases/*.sh; do
  name=$(basename "$case_file" .sh)
  case $name in
    *"$filter"*) ;;
    *) continue ;;
  esac
  casedir=$workdir/$name
  mkdir -p "$casedir"
  if (
    cd "$casedir" || exit 1
    . "$root/tests/lib.sh"
    . "$case_file"
  ) >"$workdir/$name.log" 2>&1; then
    passed=$((passed + 1))
    printf 'ok   %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n' "$name"
    sed 's/^/     /' "$workdir/$name.log"
  fi
done

printf '\n%s passed, %s failed (shell: %s)\n' "$passed" "$failed" "$shell_under_test"
if [ "$failed" -eq 0 ]; then
  exit 0
fi
exit 1
```

`tests/lib.sh`:

```sh
# Assertion helpers for the spur test suite.
#
# Sourced by tests/run.sh inside each case's own temporary directory. The
# variables $runner and $shell_under_test come from the harness.

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

# Run the runner under test; capture stdout, stderr and the exit status.
run() {
  "$shell_under_test" "$runner" "$@" >stdout 2>stderr
  status=$?
  return 0
}

assert_status() {
  [ "$status" = "$1" ] || fail "expected exit status $1, got $status"
}

# Compare stdout with the heredoc given on stdin, byte for byte.
assert_stdout_is() {
  cat > expected
  diff -u expected stdout || fail "stdout differs from expected"
}

assert_stdout_has() {
  grep -qF -- "$1" stdout || fail "stdout does not contain: $1"
}

assert_stdout_lacks() {
  grep -qF -- "$1" stdout && fail "stdout unexpectedly contains: $1"
  return 0
}

assert_stdout_matches() {
  grep -qE -- "$1" stdout || fail "stdout does not match: $1"
}

assert_stderr_has() {
  grep -qF -- "$1" stderr || fail "stderr does not contain: $1"
}

assert_stderr_lacks() {
  grep -qF -- "$1" stderr && fail "stderr unexpectedly contains: $1"
  return 0
}

assert_stderr_matches() {
  grep -qE -- "$1" stderr || fail "stderr does not match: $1"
}
```

- [ ] **Step 2: Write the failing cases**

`tests/cases/010-version.sh`:

```sh
run -V
assert_status 0
assert_stdout_matches '^spur [0-9]+\.[0-9]+\.[0-9]+$'

run --version
assert_status 0
assert_stdout_matches '^spur [0-9]+\.[0-9]+\.[0-9]+$'
```

`tests/cases/011-help.sh`:

```sh
run -h
assert_status 0
assert_stdout_has 'Usage:'
assert_stdout_has 'spur [runner flags] <task> [task arguments...]'

run --help
assert_status 0
assert_stdout_has 'Usage:'
```

`tests/cases/012-unknown-option.sh`:

```sh
run -z
assert_status 64
assert_stderr_has 'spur: unknown option: -z'

# Short flags cannot be grouped: -xn is not -x -n.
run -xn build
assert_status 64
assert_stderr_has 'spur: unknown option: -xn'
```

`tests/cases/013-option-missing-argument.sh`:

```sh
run -f
assert_status 64
assert_stderr_has 'spur: option -f requires an argument'

run -C
assert_status 64
assert_stderr_has 'spur: option -C requires an argument'
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `sh tests/run.sh`
Expected: four `FAIL` lines, `0 passed, 4 failed`, because `spur` does not
exist yet.

- [ ] **Step 4: Write the runner skeleton**

`spur`:

```sh
#!/bin/sh
# spur - Simple Portable Universal Runner
# https://github.com/esliph/spur
#
# A task runner in strict POSIX sh. There is no runtime and no build step:
# this file is the whole program.

VERSION=0.1.0

# --------------------------------------------------------------- diagnostics

# die CODE MESSAGE...
die() {
  code=$1
  shift
  printf 'spur: %s\n' "$*" >&2
  exit "$code"
}

usage() {
  cat <<'EOF'
spur - Simple Portable Universal Runner

Usage:
  spur [runner flags] <task> [task arguments...]

The first word that does not start with '-' is the task name. Everything
after it belongs to the task and is passed through untouched.

Runner flags:
  -f FILE        use FILE instead of searching for a Spurfile
  -C DIR         change to DIR before anything else
  -l, --list     list the tasks and exit
  -n             print the assembled script instead of running it
  -x             trace commands (set -x) after the preamble
  -h, --help     show this help and exit
  -V, --version  show the version and exit

Running spur with no task name lists the tasks.

Exit codes:
  64  usage error          65  malformed Spurfile
  66  Spurfile not found   67  unknown task
  68  recursion detected
A task's own exit code is propagated unchanged.
EOF
}

# ----------------------------------------------------------- argument parsing

spurfile_opt=
chdir_opt=
list_opt=
dry_opt=
trace_opt=

while [ $# -gt 0 ]; do
  case $1 in
    -f)
      [ $# -ge 2 ] || die 64 "option -f requires an argument"
      spurfile_opt=$2
      shift 2
      ;;
    -C)
      [ $# -ge 2 ] || die 64 "option -C requires an argument"
      chdir_opt=$2
      shift 2
      ;;
    -l | --list)
      list_opt=1
      shift
      ;;
    -n)
      dry_opt=1
      shift
      ;;
    -x)
      trace_opt=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -V | --version)
      printf 'spur %s\n' "$VERSION"
      exit 0
      ;;
    -*)
      die 64 "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

if [ $# -gt 0 ]; then
  task=$1
  shift
else
  task=
fi

exit 0
```

Note: the trailing `exit 0` is a placeholder removed in Task 2. Without it the
script's exit status would be whatever the last command left behind.

- [ ] **Step 5: Make the runner executable and run the tests**

Run:

```bash
chmod +x spur
sh tests/run.sh
```

Expected: `4 passed, 0 failed`.

- [ ] **Step 6: Verify the runner under dash**

Run: `SPUR_TEST_SHELL=dash sh tests/run.sh`
Expected: `4 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add spur tests
git update-index --chmod=+x spur
git commit -m "feat: add test harness and runner skeleton

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

`git update-index --chmod=+x` is needed because `core.filemode` is off on
Windows checkouts, where `chmod +x` alone does not reach the index.

---

### Task 2: Spurfile discovery and the working directory

**Files:**
- Modify: `spur` (replace the placeholder `exit 0` with discovery)
- Create: `tests/cases/020-find-in-cwd.sh`
- Create: `tests/cases/021-find-ascending.sh`
- Create: `tests/cases/022-lowercase-name.sh`
- Create: `tests/cases/023-not-found.sh`
- Create: `tests/cases/024-flag-f.sh`
- Create: `tests/cases/025-flag-f-missing.sh`
- Create: `tests/cases/026-flag-C.sh`
- Create: `tests/cases/027-flag-C-missing.sh`

**Interfaces:**
- Consumes: from Task 1, `die CODE MESSAGE`, the flag variables
  `spurfile_opt`, `chdir_opt`, `list_opt`, `dry_opt`, `trace_opt`, and `task`.
- Produces: `resolve_self` (prints the absolute path of the running script),
  `find_spurfile` (prints the path of the nearest Spurfile, returns 1 if
  none), and the globals `SPUR_BIN`, `SPUR_INVOCATION_DIR`, `SPUR_FILE`,
  `SPUR_ROOT`. After this task the process cwd is always `SPUR_ROOT`.

- [ ] **Step 1: Write the failing tests**

`tests/cases/020-find-in-cwd.sh`:

```sh
spurfile <<'EOF'
build:
  echo hi
EOF

base=$PWD
run
assert_status 0
assert_stdout_has "Spurfile: $base/Spurfile"
```

`tests/cases/021-find-ascending.sh`:

```sh
spurfile <<'EOF'
build:
  echo hi
EOF

base=$PWD
mkdir -p deep/deeper
cd deep/deeper || fail "cannot enter deep/deeper"

run
assert_status 0
assert_stdout_has "Spurfile: $base/Spurfile"
```

`tests/cases/022-lowercase-name.sh`:

```sh
cat > spurfile <<'EOF'
build:
  echo hi
EOF

base=$PWD
run
assert_status 0
assert_stdout_has "Spurfile: $base/spurfile"
```

Note: on a case-insensitive filesystem (macOS, Windows) this file is the same
file as `Spurfile`; the case still passes because the runner prints whichever
name it resolved.

`tests/cases/023-not-found.sh`:

```sh
# This case writes no Spurfile. Its ancestors are the harness directory,
# the temporary directory and /, none of which has one either.
run
assert_status 66
assert_stderr_has 'spur: no Spurfile found in'
assert_stderr_has 'or any parent directory'
```

`tests/cases/024-flag-f.sh`:

```sh
mkdir -p other
cat > other/custom.spur <<'EOF'
build:
  echo hi
EOF

base=$PWD
run -f other/custom.spur
assert_status 0
assert_stdout_has "Spurfile: $base/other/custom.spur"
```

`tests/cases/025-flag-f-missing.sh`:

```sh
run -f missing.spur
assert_status 66
assert_stderr_has 'spur: missing.spur: no such file'
```

`tests/cases/026-flag-C.sh`:

```sh
mkdir -p api
cat > api/Spurfile <<'EOF'
build:
  echo hi
EOF

base=$PWD
run -C api
assert_status 0
assert_stdout_has "Spurfile: $base/api/Spurfile"
```

`tests/cases/027-flag-C-missing.sh`:

```sh
run -C no-such-dir
assert_status 64
assert_stderr_has 'spur: cannot change directory: no-such-dir'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/run.sh 02`
Expected: the eight `02*` cases fail; the runner prints nothing and exits 0,
so every `assert_stdout_has`/`assert_status` on an error path fails.

- [ ] **Step 3: Implement discovery**

Insert `resolve_self` and `find_spurfile` after `usage()` in `spur`:

```sh
# ------------------------------------------------------------------ locating

# Absolute path of this script. Must run before any directory change.
resolve_self() {
  case $0 in
    */*)
      printf '%s/%s\n' "$(cd "$(dirname "$0")" && pwd)" "$(basename "$0")"
      ;;
    *)
      self=$(command -v -- "$0" 2>/dev/null) || self=$0
      case $self in
        /*) printf '%s\n' "$self" ;;
        *) printf '%s/%s\n' "$(cd "$(dirname "$self")" && pwd)" "$(basename "$self")" ;;
      esac
      ;;
  esac
}

# Print the nearest Spurfile, searching upwards from the current directory.
find_spurfile() {
  dir=$PWD
  while :; do
    if [ -f "$dir/Spurfile" ]; then
      printf '%s/Spurfile\n' "$dir"
      return 0
    fi
    if [ -f "$dir/spurfile" ]; then
      printf '%s/spurfile\n' "$dir"
      return 0
    fi
    parent=$(dirname "$dir")
    [ "$parent" = "$dir" ] && return 1
    dir=$parent
  done
}
```

Then replace the placeholder `exit 0` at the end of the file with:

```sh
# ---------------------------------------------------------------------- setup

SPUR_BIN=$(resolve_self)
SPUR_INVOCATION_DIR=$PWD

if [ -n "$chdir_opt" ]; then
  cd "$chdir_opt" || die 64 "cannot change directory: $chdir_opt"
fi

if [ -n "$spurfile_opt" ]; then
  [ -f "$spurfile_opt" ] || die 66 "$spurfile_opt: no such file"
  SPUR_FILE=$(cd "$(dirname "$spurfile_opt")" && pwd)/$(basename "$spurfile_opt")
else
  SPUR_FILE=$(find_spurfile) ||
    die 66 "no Spurfile found in $PWD or any parent directory"
fi

SPUR_ROOT=$(dirname "$SPUR_FILE")
cd "$SPUR_ROOT" || die 66 "cannot enter $SPUR_ROOT"

printf 'Spurfile: %s\n\n' "$SPUR_FILE"
exit 0
```

The final `printf`/`exit 0` is the observable behavior for this task and
becomes the header of `--list` in Task 3.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/run.sh`
Expected: `12 passed, 0 failed`.

- [ ] **Step 5: Verify under dash**

Run: `SPUR_TEST_SHELL=dash sh tests/run.sh`
Expected: `12 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add spur tests
git commit -m "feat: locate the Spurfile and anchor the working directory

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The parser and `--list`

**Files:**
- Modify: `spur`
- Create: `tests/cases/030-list.sh`
- Create: `tests/cases/031-list-file-order.sh`
- Create: `tests/cases/032-list-flag.sh`
- Create: `tests/cases/033-comment-between-tasks.sh`
- Create: `tests/cases/034-syntax-error.sh`
- Create: `tests/cases/035-duplicate-task.sh`
- Create: `tests/cases/036-prerequisites-rejected.sh`
- Create: `tests/cases/037-empty-spurfile.sh`

**Interfaces:**
- Consumes: from Task 2, `SPUR_FILE`, `SPUR_ROOT`, `die`.
- Produces: `AWK_PARSER` (the awk program, a single-quoted string),
  `run_parser MODE WANT` (runs the parser, leaves its output in the global
  `PARSER_OUT`, returns the awk exit status), and `parser_error STATUS`
  (prints `PARSER_OUT` as a diagnostic and exits with `STATUS`). Modes are
  `list`, `preamble` and `body`. Later tasks call `run_parser preamble ""`
  and `run_parser body "$task"`.

**Why `run_parser` is a function that sets a global:** `PARSER_OUT=$(awk ...)`
must run in the current shell. Wrapping it so the caller writes
`out=$(parse body x)` would put `die` inside a command substitution subshell,
where `exit` kills the subshell and the script keeps going with an empty body.

- [ ] **Step 1: Write the failing tests**

`tests/cases/030-list.sh`:

```sh
spurfile <<'EOF'
IMAGE=myapp:latest

build: ## build the image
  docker build -t "$IMAGE" .

test: ## run the tests
  pytest -q "$@"

deploy:
  ./deploy.sh
EOF

run --list
assert_status 0
assert_stdout_is <<EOF
Spurfile: $PWD/Spurfile

  build    build the image
  test     run the tests
  deploy
EOF
```

The description column is `2 + (longest name) + 3`. Here the longest name is
`deploy` (6), so descriptions start at column 11 (zero-based). A task with no
description prints no trailing whitespace.

`tests/cases/031-list-file-order.sh`:

```sh
spurfile <<'EOF'
zebra: ## last alphabetically, first in the file
  echo z

alpha: ## first alphabetically, last in the file
  echo a
EOF

run
assert_status 0
assert_stdout_is <<EOF
Spurfile: $PWD/Spurfile

  zebra   last alphabetically, first in the file
  alpha   first alphabetically, last in the file
EOF
```

`tests/cases/032-list-flag.sh`:

```sh
spurfile <<'EOF'
build: ## build it
  echo building
EOF

# -l lists and exits even when a task name follows.
run -l build
assert_status 0
assert_stdout_has '  build   build it'
assert_stdout_lacks 'building'
```

`tests/cases/033-comment-between-tasks.sh`:

```sh
spurfile <<'EOF'
build: ## build it
  echo building

# This comment sits at column zero between two tasks.
test: ## test it
  echo testing
EOF

run --list
assert_status 0
assert_stdout_has '  build   build it'
assert_stdout_has '  test    test it'
```

`tests/cases/034-syntax-error.sh`:

```sh
spurfile <<'EOF'
build:
  echo building
this is not a task header
EOF

run --list
assert_status 65
assert_stderr_has 'Spurfile:3: syntax error: expected a task header'
```

`tests/cases/035-duplicate-task.sh`:

```sh
spurfile <<'EOF'
build:
  echo one

build:
  echo two
EOF

run --list
assert_status 65
assert_stderr_has 'Spurfile:4: duplicate task: build'
```

`tests/cases/036-prerequisites-rejected.sh`:

```sh
spurfile <<'EOF'
build: deps
  echo building
EOF

run --list
assert_status 65
assert_stderr_has 'Spurfile:1: task header takes no prerequisites: build'
```

`tests/cases/037-empty-spurfile.sh`:

```sh
spurfile <<'EOF'
# nothing here but a comment
EOF

run --list
assert_status 0
assert_stdout_has '(no tasks defined)'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/run.sh 03`
Expected: all eight `03*` cases fail — the runner still prints only the
`Spurfile:` header and exits 0.

- [ ] **Step 3: Add the awk parser**

Insert this block in `spur` after `find_spurfile`. The program is held in a
single-quoted string, so it must contain no single quote character.

```sh
# ------------------------------------------------------------------- parsing

# The Spurfile parser. Modes:
#   list      one formatted line per task
#   preamble  every line before the first task header
#   body      the dedented body of the task named by "want"
# Diagnostics go to stdout; the exit status carries the meaning (65 syntax,
# 67 unknown task), because /dev/stderr is not portable across awks.
AWK_PARSER='
function err(msg) { printf "%s:%d: %s\n", file, NR, msg; failed = 1; exit 65 }
function ws(s) { match(s, /^[ \t]*/); return substr(s, 1, RLENGTH) }
function cprefix(a, b,   i, n) {
  n = length(a); if (length(b) < n) n = length(b)
  for (i = 1; i <= n; i++) if (substr(a, i, 1) != substr(b, i, 1)) return substr(a, 1, i - 1)
  return substr(a, 1, n)
}
BEGIN { started = 0; in_body = 0; capturing = 0; found = 0; nb = 0; npre = 0; nt = 0; maxlen = 0 }
{
  line = $0
  sub(/\r$/, "", line)
  if (line ~ /^[ \t]*$/) {
    if (in_body) { if (capturing) body[++nb] = line }
    else if (!started) pre[++npre] = line
    next
  }
  if (line ~ /^[ \t]/) {
    if (in_body) { if (capturing) body[++nb] = line; next }
    if (!started) { pre[++npre] = line; next }
    err("indented line does not belong to any task")
  }
  if (line ~ /^#/) { in_body = 0; capturing = 0; if (!started) pre[++npre] = line; next }
  if (line ~ /^[A-Za-z0-9_.-]+:/) {
    colon = index(line, ":")
    name = substr(line, 1, colon - 1)
    rest = substr(line, colon + 1)
    h = index(rest, "##")
    if (h > 0) { lead = substr(rest, 1, h - 1); desc = substr(rest, h + 2) }
    else { lead = rest; desc = "" }
    if (lead ~ /[^ \t]/) err("task header takes no prerequisites: " name)
    sub(/^[ \t]+/, "", desc); sub(/[ \t]+$/, "", desc)
    if (name in seen) err("duplicate task: " name)
    seen[name] = 1
    tname[++nt] = name; tdesc[nt] = desc
    if (length(name) > maxlen) maxlen = length(name)
    started = 1; in_body = 1
    capturing = (mode == "body" && name == want)
    if (capturing) found = 1
    next
  }
  if (!started) { pre[++npre] = line; next }
  err("syntax error: expected a task header")
}
END {
  if (failed) exit 65
  if (mode == "list") {
    fmt = "  %-" (maxlen + 3) "s%s\n"
    for (i = 1; i <= nt; i++) {
      if (tdesc[i] == "") printf "  %s\n", tname[i]
      else printf fmt, tname[i], tdesc[i]
    }
    exit 0
  }
  if (mode == "preamble") {
    for (i = 1; i <= npre; i++) print pre[i]
    exit 0
  }
  if (mode == "body") {
    if (!found) { printf "unknown task: %s\n", want; exit 67 }
    while (nb > 0 && body[nb] ~ /^[ \t]*$/) nb--
    pfx = ""; first = 1
    for (i = 1; i <= nb; i++) {
      if (body[i] ~ /^[ \t]*$/) continue
      if (first) { pfx = ws(body[i]); first = 0 }
      else pfx = cprefix(pfx, ws(body[i]))
    }
    n = length(pfx)
    for (i = 1; i <= nb; i++) {
      if (body[i] ~ /^[ \t]*$/) print ""
      else print substr(body[i], n + 1)
    }
    exit 0
  }
}
'

PARSER_OUT=

# run_parser MODE WANT -- leaves the parser output in PARSER_OUT and returns
# the parser exit status. Must stay a function, never a command substitution,
# so that the caller can exit on failure.
run_parser() {
  PARSER_OUT=$(
    awk -v mode="$1" -v want="$2" -v file="$(basename "$SPUR_FILE")" \
      "$AWK_PARSER" "$SPUR_FILE"
  )
}

# parser_error STATUS -- report PARSER_OUT and exit.
parser_error() {
  printf 'spur: %s\n' "$PARSER_OUT" >&2
  if [ "$1" -eq 67 ]; then
    printf "spur: run 'spur --list' to see the available tasks\n" >&2
  fi
  exit "$1"
}

list_tasks() {
  run_parser list "" || parser_error $?
  printf 'Spurfile: %s\n\n' "$SPUR_FILE"
  if [ -n "$PARSER_OUT" ]; then
    printf '%s\n' "$PARSER_OUT"
  else
    printf '  (no tasks defined)\n'
  fi
}
```

Note: `err()` sets `failed` before calling `exit`, and `END` re-checks it,
because in awk `exit` inside a rule still runs the `END` block.

- [ ] **Step 4: Wire `--list` into the main flow**

Replace the two placeholder lines at the end of `spur`

```sh
printf 'Spurfile: %s\n\n' "$SPUR_FILE"
exit 0
```

with:

```sh
# ----------------------------------------------------------------- listing

if [ -n "$list_opt" ] || [ -z "$task" ]; then
  if [ -z "$task" ] && { [ -n "$dry_opt" ] || [ -n "$trace_opt" ]; }; then
    die 64 "no task given"
  fi
  list_tasks
  exit 0
fi

exit 0
```

The trailing `exit 0` is a placeholder removed in Task 4.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `sh tests/run.sh`
Expected: `20 passed, 0 failed`.

- [ ] **Step 6: Verify under dash**

Run: `SPUR_TEST_SHELL=dash sh tests/run.sh`
Expected: `20 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add spur tests
git commit -m "feat: parse the Spurfile and implement --list

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Script assembly and `-n`

**Files:**
- Modify: `spur`
- Create: `tests/cases/040-dry-run.sh`
- Create: `tests/cases/041-dedent.sh`
- Create: `tests/cases/042-blank-lines-in-body.sh`
- Create: `tests/cases/043-unknown-task.sh`
- Create: `tests/cases/044-dry-run-without-task.sh`
- Create: `tests/cases/045-no-expansion-by-runner.sh`

**Interfaces:**
- Consumes: from Task 3, `run_parser`, `parser_error`, `PARSER_OUT`.
- Produces: `build_script TASK`, which leaves the assembled script in the
  global `script`. Its shape is `set -e`, then the injected `spur` function,
  then the user preamble, then (Task 7) the trace lines, then the task body.

- [ ] **Step 1: Write the failing tests**

`tests/cases/040-dry-run.sh`:

```sh
spurfile <<'EOF'
FOO=bar

hello: ## greet
  echo "$FOO"
EOF

run -n hello
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
FOO=bar
echo "$FOO"
EOF
```

The blank line after `FOO=bar` is gone because command substitution strips
trailing newlines from the preamble. Blank lines *between* preamble lines
survive.

`tests/cases/041-dedent.sh`:

```sh
spurfile <<'EOF'
nested:
    if true; then
      echo inner
    fi
EOF

run -n nested
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
if true; then
  echo inner
fi
EOF
```

There is no blank line for the empty preamble: command substitution strips
trailing newlines at every assembly step. The body kept its relative
indentation after the common four-space prefix was removed.

`tests/cases/042-blank-lines-in-body.sh`:

```sh
spurfile <<'EOF'
gapped:
  echo one

  echo two

other:
  echo three
EOF

run -n gapped
assert_status 0
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
echo one

echo two
EOF
```

The blank line between the two `echo`s belongs to the body; the trailing one
before `other:` is trimmed.

`tests/cases/043-unknown-task.sh`:

```sh
spurfile <<'EOF'
build:
  echo building
EOF

run nope
assert_status 67
assert_stderr_has 'spur: unknown task: nope'
assert_stderr_has "run 'spur --list'"
```

`tests/cases/044-dry-run-without-task.sh`:

```sh
spurfile <<'EOF'
build:
  echo building
EOF

run -n
assert_status 64
assert_stderr_has 'spur: no task given'

run -x
assert_status 64
assert_stderr_has 'spur: no task given'
```

`tests/cases/045-no-expansion-by-runner.sh`:

```sh
spurfile <<'EOF'
raw:
  echo "$IMAGE ${x:-y} $(date) $$"
EOF

run -n raw
assert_status 0
assert_stdout_has 'echo "$IMAGE ${x:-y} $(date) $$"'
```

The runner expands nothing: the body reaches `sh` byte for byte.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/run.sh 04`
Expected: the six `04*` cases fail; `spur -n hello` currently prints nothing
and exits 0.

- [ ] **Step 3: Implement assembly**

Add after `list_tasks()` in `spur`:

```sh
# ------------------------------------------------------------------ assembly

PRELUDE='set -e
spur() { "$SPUR_BIN" "$@"; }'

script=

# build_script TASK -- leaves the assembled script in the global "script".
build_script() {
  run_parser body "$1" || parser_error $?
  body=$PARSER_OUT
  run_parser preamble "" || parser_error $?
  preamble=$PARSER_OUT

  script=$(printf '%s\n%s\n' "$PRELUDE" "$preamble")
  script=$(printf '%s\n%s\n' "$script" "$body")
}
```

Then replace the placeholder `exit 0` at the end of the file with:

```sh
# ---------------------------------------------------------------- execution

build_script "$task"

if [ -n "$dry_opt" ]; then
  printf '%s\n' "$script"
  exit 0
fi

exit 0
```

The second `exit 0` is a placeholder removed in Task 5.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/run.sh`
Expected: `26 passed, 0 failed`.

- [ ] **Step 5: Verify under dash**

Run: `SPUR_TEST_SHELL=dash sh tests/run.sh`
Expected: `26 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add spur tests
git commit -m "feat: assemble the task script and implement -n

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Execution

**Files:**
- Modify: `spur`
- Create: `tests/cases/050-run-task.sh`
- Create: `tests/cases/051-exit-code-propagation.sh`
- Create: `tests/cases/052-argument-passthrough.sh`
- Create: `tests/cases/053-set-e-aborts.sh`
- Create: `tests/cases/054-working-directory.sh`
- Create: `tests/cases/055-environment.sh`
- Create: `tests/cases/056-stdin-is-free.sh`
- Create: `tests/cases/057-error-label.sh`
- Create: `tests/cases/058-task-name-characters.sh`
- Create: `tests/cases/059-working-directory-with-f.sh`

**Interfaces:**
- Consumes: from Task 4, `build_script` and `script`; from Task 2, `SPUR_BIN`,
  `SPUR_ROOT`, `SPUR_INVOCATION_DIR`.
- Produces: the final `exec sh -c "$script" "spur $task" "$@"` and the
  exported environment `SPUR_BIN`, `SPUR_ROOT`, `SPUR_INVOCATION_DIR`,
  `SPUR_TASK`.

- [ ] **Step 1: Write the failing tests**

`tests/cases/050-run-task.sh`:

```sh
spurfile <<'EOF'
PREFIX=hello

greet:
  echo "$PREFIX world"
EOF

run greet
assert_status 0
assert_stdout_is <<'EOF'
hello world
EOF
```

`tests/cases/051-exit-code-propagation.sh`:

```sh
spurfile <<'EOF'
boom:
  exit 42
EOF

run boom
assert_status 42

# A runner error code must never be mistaken for a task code.
run -f missing
assert_status 66
```

`tests/cases/052-argument-passthrough.sh`:

```sh
spurfile <<'EOF'
show:
  printf 'count=%s\n' "$#"
  for a in "$@"; do printf 'arg=[%s]\n' "$a"; done
EOF

run show -k foo "two words" -vv
assert_status 0
assert_stdout_is <<'EOF'
count=4
arg=[-k]
arg=[foo]
arg=[two words]
arg=[-vv]
EOF
```

`tests/cases/053-set-e-aborts.sh`:

```sh
spurfile <<'EOF'
chain:
  echo first
  false
  echo never
EOF

run chain
assert_status 1
assert_stdout_has 'first'
assert_stdout_lacks 'never'
```

`tests/cases/054-working-directory.sh`:

```sh
spurfile <<'EOF'
where:
  pwd
EOF

base=$PWD
mkdir -p deep/deeper
cd deep/deeper || fail "cannot enter deep/deeper"

run where
assert_status 0
assert_stdout_is <<EOF
$base
EOF
```

`tests/cases/055-environment.sh`:

```sh
spurfile <<'EOF'
env:
  printf 'task=%s\n' "$SPUR_TASK"
  printf 'root=%s\n' "$SPUR_ROOT"
  printf 'from=%s\n' "$SPUR_INVOCATION_DIR"
  [ -f "$SPUR_BIN" ] && printf 'bin=ok\n'
EOF

base=$PWD
mkdir -p sub
cd sub || fail "cannot enter sub"

run env
assert_status 0
assert_stdout_is <<EOF
task=env
root=$base
from=$base/sub
bin=ok
EOF
```

`tests/cases/056-stdin-is-free.sh`:

```sh
spurfile <<'EOF'
read-line:
  read line
  printf 'got=[%s]\n' "$line"
EOF

printf 'from stdin\n' | "$shell_under_test" "$runner" read-line >stdout 2>stderr
status=$?
assert_status 0
assert_stdout_is <<'EOF'
got=[from stdin]
EOF
```

`tests/cases/057-error-label.sh`:

```sh
spurfile <<'EOF'
broken:
  no-such-command-anywhere
EOF

run broken
assert_status 127
assert_stderr_has 'spur broken'
```

The `$0` given to `sh -c` is `spur broken`, so the shell's own diagnostic is
labelled with the task that produced it.

`tests/cases/058-task-name-characters.sh`:

```sh
spurfile <<'EOF'
db-reset: ## recreate the database
  echo resetting

docker.build:
  echo building
EOF

run db-reset
assert_status 0
assert_stdout_is <<'EOF'
resetting
EOF

run docker.build
assert_status 0
assert_stdout_is <<'EOF'
building
EOF
```

Task names take `-` and `.` because tasks are not shell functions: the body
is extracted as text.

`tests/cases/059-working-directory-with-f.sh`:

```sh
mkdir -p other
cat > other/custom.spur <<'EOF'
where:
  pwd
EOF

base=$PWD
run -f other/custom.spur where
assert_status 0
assert_stdout_is <<EOF
$base/other
EOF
```

With `-f`, the task's working directory is the directory holding the file
that was pointed at, not the one the user called from.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/run.sh 05`
Expected: the ten `05*` cases fail; tasks currently produce no output and
always exit 0.

- [ ] **Step 3: Implement execution**

Replace the placeholder `exit 0` at the end of `spur` with:

```sh
SPUR_TASK=$task
export SPUR_BIN SPUR_ROOT SPUR_INVOCATION_DIR SPUR_TASK

exec sh -c "$script" "spur $task" "$@"
```

`exec` replaces the runner process: the task's exit code, its signals and its
stdin are the runner's, with no wrapper left in between.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/run.sh`
Expected: `36 passed, 0 failed`.

- [ ] **Step 5: Verify under dash**

Run: `SPUR_TEST_SHELL=dash sh tests/run.sh`
Expected: `36 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add spur tests
git commit -m "feat: run tasks with argument passthrough and exit code propagation

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Recursion guard and chained calls

**Files:**
- Modify: `spur`
- Create: `tests/cases/060-chained-call.sh`
- Create: `tests/cases/061-chained-call-relative-path.sh`
- Create: `tests/cases/062-chained-call-arguments.sh`
- Create: `tests/cases/063-recursion-detected.sh`
- Create: `tests/cases/064-repeated-call-allowed.sh`

**Interfaces:**
- Consumes: from Task 5, the export block and the `exec` line; from Task 4,
  the `PRELUDE` that defines the injected `spur` function.
- Produces: `SPUR_STACK`, exported and space-separated, plus the guard that
  turns an ancestor repeat into exit 68.

- [ ] **Step 1: Write the failing tests**

`tests/cases/060-chained-call.sh`:

```sh
spurfile <<'EOF'
deps:
  echo installing deps

build:
  spur deps
  echo building
EOF

run build
assert_status 0
assert_stdout_is <<'EOF'
installing deps
building
EOF
```

`tests/cases/061-chained-call-relative-path.sh`:

```sh
spurfile <<'EOF'
deps:
  echo installing deps

build:
  spur deps
  echo building
EOF

cp "$runner" ./vendored-spur
chmod +x ./vendored-spur

# Invoked by a relative path, outside the PATH, from another directory.
mkdir -p sub
cd sub || fail "cannot enter sub"
"$shell_under_test" ../vendored-spur build >stdout 2>stderr
status=$?

assert_status 0
assert_stdout_is <<'EOF'
installing deps
building
EOF
```

`tests/cases/062-chained-call-arguments.sh`:

```sh
spurfile <<'EOF'
lint:
  printf 'lint args=[%s]\n' "$*"

check:
  spur lint --fix
EOF

run check
assert_status 0
assert_stdout_is <<'EOF'
lint args=[--fix]
EOF
```

`tests/cases/063-recursion-detected.sh`:

```sh
spurfile <<'EOF'
a:
  spur b

b:
  spur a
EOF

run a
assert_status 68
assert_stderr_has 'spur: recursion detected: a -> b -> a'
```

`tests/cases/064-repeated-call-allowed.sh`:

```sh
spurfile <<'EOF'
leaf:
  echo leaf

twice:
  spur leaf
  spur leaf
EOF

run twice
assert_status 0
assert_stdout_is <<'EOF'
leaf
leaf
EOF
```

Two sibling calls are not recursion: the guard only looks at ancestors.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/run.sh 06`
Expected: `060`, `061`, `062` and `064` pass already (the injected function
was added in Task 4), while `063` fails — the mutual call loops until the
shell gives up instead of exiting 68. Confirm `063` is the failing one; if
`063` hangs, interrupt it with Ctrl-C and treat that as the failure.

- [ ] **Step 3: Implement the guard**

In `spur`, replace the export block from Task 5 with:

```sh
SPUR_TASK=$task

case " ${SPUR_STACK:-} " in
  *" $task "*)
    chain=
    # Task names cannot contain spaces, so splitting the stack is safe.
    # shellcheck disable=SC2086
    for frame in ${SPUR_STACK:-}; do
      chain=${chain:+$chain -> }$frame
    done
    die 68 "recursion detected: ${chain:+$chain -> }$task"
    ;;
esac

SPUR_STACK=${SPUR_STACK:+$SPUR_STACK }$task
export SPUR_BIN SPUR_ROOT SPUR_INVOCATION_DIR SPUR_TASK SPUR_STACK

exec sh -c "$script" "spur $task" "$@"
```

Place the guard **before** `build_script "$task"` in the main flow, matching
the pipeline in the design document, so a recursive call fails before the
parser runs. Concretely, the tail of `spur` reads:

```sh
# ---------------------------------------------------------------- execution

SPUR_TASK=$task

case " ${SPUR_STACK:-} " in
  *" $task "*)
    chain=
    # shellcheck disable=SC2086
    for frame in ${SPUR_STACK:-}; do
      chain=${chain:+$chain -> }$frame
    done
    die 68 "recursion detected: ${chain:+$chain -> }$task"
    ;;
esac

build_script "$task"

if [ -n "$dry_opt" ]; then
  printf '%s\n' "$script"
  exit 0
fi

SPUR_STACK=${SPUR_STACK:+$SPUR_STACK }$task
export SPUR_BIN SPUR_ROOT SPUR_INVOCATION_DIR SPUR_TASK SPUR_STACK

exec sh -c "$script" "spur $task" "$@"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/run.sh`
Expected: `41 passed, 0 failed`.

- [ ] **Step 5: Verify under dash**

Run: `SPUR_TEST_SHELL=dash sh tests/run.sh`
Expected: `41 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add spur tests
git commit -m "feat: guard against recursive task chains

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: The `-x` trace flag

**Files:**
- Modify: `spur`
- Create: `tests/cases/070-trace.sh`
- Create: `tests/cases/071-trace-skips-preamble.sh`
- Create: `tests/cases/072-dry-run-beats-trace.sh`

**Interfaces:**
- Consumes: from Task 4, `build_script` and the `trace_opt` flag from Task 1.
- Produces: the trace lines inserted between the preamble and the body.

- [ ] **Step 1: Write the failing tests**

`tests/cases/070-trace.sh`:

```sh
spurfile <<'EOF'
IMAGE=myapp:latest

show:
  echo "building $IMAGE"
EOF

run -x show
assert_status 0
assert_stdout_has 'building myapp:latest'
# The trace shows the expanded command, with a lean PS4.
assert_stderr_has '$ echo building myapp:latest'
```

`tests/cases/071-trace-skips-preamble.sh`:

```sh
spurfile <<'EOF'
SECRET=preamble-value
helper() { echo helped; }

show:
  echo visible
EOF

run -x show
assert_status 0
assert_stderr_lacks 'SECRET=preamble-value'
assert_stderr_has '$ echo visible'
```

`tests/cases/072-dry-run-beats-trace.sh`:

```sh
spurfile <<'EOF'
show:
  echo visible
EOF

run -n -x show
assert_status 0
assert_stdout_has 'set -x'
# Printed, not executed: the echo never ran.
assert_stdout_is <<'EOF'
set -e
spur() { "$SPUR_BIN" "$@"; }
PS4='$ '
set -x
echo visible
EOF
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `sh tests/run.sh 07`
Expected: the three `07*` cases fail; `-x` is parsed but ignored.

- [ ] **Step 3: Implement the trace**

In `build_script`, insert the trace lines between the preamble and the body:

```sh
build_script() {
  run_parser body "$1" || parser_error $?
  body=$PARSER_OUT
  run_parser preamble "" || parser_error $?
  preamble=$PARSER_OUT

  script=$(printf '%s\n%s\n' "$PRELUDE" "$preamble")
  if [ -n "$trace_opt" ]; then
    script=$(printf "%s\nPS4='\$ '\nset -x\n" "$script")
  fi
  script=$(printf '%s\n%s\n' "$script" "$body")
}
```

Inside a double-quoted `printf` format, `\$` produces a literal `$`, so the
generated line is exactly `PS4='$ '`. Putting `set -x` after the preamble is
what keeps variable assignments and function definitions out of the trace.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `sh tests/run.sh`
Expected: `44 passed, 0 failed`.

- [ ] **Step 5: Verify under dash and bash**

Run:

```bash
SPUR_TEST_SHELL=dash sh tests/run.sh
SPUR_TEST_SHELL=bash sh tests/run.sh
```

Expected: `44 passed, 0 failed` for both.

- [ ] **Step 6: Commit**

```bash
git add spur tests
git commit -m "feat: add the -x trace flag

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Dogfooding Spurfile and the English-facing documentation

**Files:**
- Create: `Spurfile`
- Create: `README.md`
- Create: `CONTRIBUTING.md`
- Create: `LICENSE`

**Interfaces:**
- Consumes: the finished runner and the harness contract from Task 1
  (`sh tests/run.sh`, `SPUR_TEST_SHELL`).
- Produces: the tasks `test`, `test-all`, `lint` and `check`, which Task 9's
  CI workflow calls.

- [ ] **Step 1: Write the Spurfile**

`Spurfile`:

```sh
# Spurfile for spur itself. If these tasks are uncomfortable to write, the
# design is wrong and we find out in the first week.
HARNESS=tests/run.sh
SOURCES="spur tests/run.sh tests/lib.sh"

test: ## run the behavior tests
  sh "$HARNESS" "$@"

test-all: ## run the tests under every POSIX shell available locally
  for candidate in sh dash bash; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    printf '== %s\n' "$candidate"
    SPUR_TEST_SHELL=$candidate sh "$HARNESS" "$@"
  done

lint: ## run shellcheck over the runner and the test suite
  shellcheck -s sh $SOURCES tests/cases/*.sh

check: ## lint and test
  spur lint
  spur test
```

`check` calling `spur lint` is deliberate: it exercises the injected `spur`
function on every run.

- [ ] **Step 2: Verify the Spurfile works**

Run:

```bash
./spur --list
./spur test
./spur test-all
```

Expected: `--list` shows the four tasks with their descriptions; `test` prints
`44 passed, 0 failed`; `test-all` repeats that for each shell found.
`./spur lint` will fail until `shellcheck` is installed locally — that is
expected, and CI is what enforces it (Task 9).

- [ ] **Step 3: Write the README**

`README.md`:

````markdown
# spur

**Simple Portable Universal Runner** — a task runner in strict POSIX sh.

`spur` reads a `Spurfile`, lists the tasks, and runs each one in a single
shell with positional argument passthrough. There is nothing to compile and
no runtime to install: it is one shell script that runs on any Unix,
including a minimal Alpine container, where `just` and Task need a binary and
`make` is not always present.

The scope is deliberately smaller than make's: **spur runs tasks, it does not
build software.** No dependency graph, no timestamp-based rebuilds, no
pattern rules.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/esliph/spur/main/spur \
  -o ~/.local/bin/spur && chmod +x ~/.local/bin/spur
```

Or vendor it: copy `spur` into your repository and commit it. Anyone who
clones runs `./spur test` without installing anything, and chained calls
still work because the runner injects a `spur` function pointing at itself.

## A Spurfile

```sh
# Everything before the first task is the preamble: plain shell, injected at
# the top of every task that runs.
IMAGE=myapp:latest
: "${ENV:=dev}"
[ -f .env ] && . ./.env

_log() { printf '>> %s\n' "$1"; }

build: ## build the image
  _log "building $IMAGE"
  docker build -t "$IMAGE" .

test: ## run the tests
  spur build
  pytest -q "$@"

db-reset: ## recreate the database (destructive)
  dropdb --if-exists app && createdb app
```

```console
$ spur --list
Spurfile: /home/dan/project/Spurfile

  build      build the image
  test       run the tests
  db-reset   recreate the database (destructive)

$ spur test -k login -vv
```

## The language

- A line matching `^[A-Za-z0-9_.-]+:` opens a task. Names may contain `-` and
  `.` (`db-reset`, `docker.build`).
- `## text` in the header is the description shown by `--list`. A task
  without one is still runnable.
- The body is indented. Spaces are canonical; a tab is accepted and never
  required.
- Before running, the runner removes the longest common indentation from the
  body, so `if`, `for` and heredocs keep their relative shape.
- Blank lines inside a body belong to the body. Only a line with content at
  column zero ends it.
- Everything before the first task is the preamble.
- A `#` comment at column zero is allowed anywhere.
- **The runner expands nothing.** `$IMAGE`, `$(date)`, `${x:-y}` and `$$`
  reach the shell untouched.
- Task headers take no prerequisites: `build: deps` is an error. Call
  `spur deps` from the body instead.

## The CLI

```
spur [runner flags] <task> [task arguments...]
```

**The first word that does not start with `-` is the task name. Everything
after it belongs to the task, untouched.**

```sh
spur -n test           # -n is the runner's (dry run of 'test')
spur test -n           # -n is the task's, arriving as "$1"
spur -C api test -k x  # -C api is the runner's; -k x is the task's
```

| Flag | Effect |
|---|---|
| `-f FILE` | use FILE instead of searching for a Spurfile |
| `-C DIR` | change to DIR before anything else |
| `-l`, `--list` | list the tasks and exit |
| `-n` | print the assembled script instead of running it |
| `-x` | trace commands (`set -x`) after the preamble, with `PS4='$ '` |
| `-h`, `--help` | show help |
| `-V`, `--version` | show the version |

`spur` with no task name lists the tasks. Short flags cannot be grouped
(`-xn` is not `-x -n`).

## How a task runs

The runner assembles `set -e` plus an injected `spur` function, plus your
preamble, plus the task body, and hands the whole thing to
`sh -c "$script" "spur <task>" "$@"`. That single call is why stdin stays
free (interactive tasks work), why there is no temporary file, and why the
shell labels its errors `spur build: line 3: ...`.

`set -e` is on, `set -u` is off. Put `set -u` in your preamble if you want it.

### The Spurfile search

`spur` looks for `Spurfile`, then `spurfile`, in the current directory, then
walks up to `/`. Both spellings exist because macOS and Windows filesystems
are case-insensitive while Linux is not. Every task runs in the directory
that holds the Spurfile in use; `SPUR_INVOCATION_DIR` preserves where you
called from.

### Environment

| Variable | Contents |
|---|---|
| `SPUR_BIN` | absolute path of the runner |
| `SPUR_ROOT` | the Spurfile's directory (= the task's working directory) |
| `SPUR_INVOCATION_DIR` | the directory you called from |
| `SPUR_TASK` | the running task's name |
| `SPUR_STACK` | the call chain, used by the recursion guard |

### Exit codes

A task's own exit code is propagated unchanged. Runner errors use the
`sysexits` range so they never collide with one.

| Code | Meaning |
|---|---|
| *(the task's)* | propagated unchanged |
| 64 | usage error |
| 65 | malformed Spurfile |
| 66 | Spurfile not found |
| 67 | unknown task |
| 68 | recursion detected |

## Coming from make

| make | spur |
|---|---|
| `make <target>` | `spur <task>` |
| mandatory TAB | any indentation; spaces are canonical |
| one shell per recipe line | one shell for the whole body: `cd` and variables persist |
| `$$` to escape `$` | nothing is expanded; `$` arrives intact |
| `.PHONY` | every task is phony by construction |
| `@` per line | `spur -x` is off by default; silence a stretch with `{ set +x; } 2>/dev/null` |
| `-` per line | `|| true` |
| `target: deps` | call `spur deps` from the body |
| `include`, `ifeq` | the preamble has real `.` and `if` |
| `$(MAKE) -C sub` | `spur -C sub build` |

## Known limitations

1. **A task can run more than once.** With no graph there is no dedup: if
   `build` calls `deps` and `lint` calls `deps`, `deps` runs twice. That is
   the price of explicit calls, and the gain is that argument passthrough
   stays symmetric and visible in the body.
2. **`-n` does not expand the call chain.** It shows the assembled script of
   the task you asked for, and only that. A `spur deps` inside a body happens
   at run time, and discovering it statically would mean interpreting shell.
3. **make's per-line `@` is not implementable.** make dispatches one line at
   a time; spur hands the whole block to one `sh` and does not know where
   each command begins. Use `spur -x` for the whole invocation, or
   `{ set +x; } 2>/dev/null` … `set -x` for a stretch (the redirection is
   needed because a bare `set +x` echoes itself before turning off).
4. **The preamble runs for every task.** Irrelevant when it is cheap
   (assignments, `.env`, functions); costly if you put real work there.
5. **No native Windows.** spur needs a POSIX shell: Git Bash, MSYS2, WSL or
   Cygwin. That is make's requirement too, so it is not a regression.
   "Portable" here means *runs on any Unix, under any POSIX shell, with no
   runtime installed* — not *runs natively everywhere*.
6. **Chained calls do not inherit `-f`.** Inside a body, `spur other` finds
   the Spurfile by the usual upward search from `SPUR_ROOT`. Propagating `-f`
   would break `spur -C sub build` in a body.

## License

MIT. See [LICENSE](LICENSE).
````

- [ ] **Step 4: Write CONTRIBUTING**

`CONTRIBUTING.md`:

```markdown
# Contributing

## Running the tests

```sh
sh tests/run.sh          # or: ./spur test
sh tests/run.sh list     # only cases whose name contains "list"
```

The harness has no dependencies: each case gets its own temporary directory
under `/tmp` (override with `SPUR_TEST_TMPDIR`), writes a `Spurfile`, runs the
runner, and compares stdout, stderr and the exit status. `bats` and
`shellspec` were both rejected: a tool that sells itself as zero-dependency
cannot require a framework to run its own tests.

## The shell matrix

"Strict POSIX" is a promise until a matrix makes it a fact.

```sh
SPUR_TEST_SHELL=dash sh tests/run.sh   # the strictest; if it passes here, it is POSIX
SPUR_TEST_SHELL=bash sh tests/run.sh
./spur test-all                        # every shell found locally
```

CI adds busybox ash (Alpine, via Docker) and `shellcheck -s sh`.

## Writing a case

Create `tests/cases/NNN-what-it-checks.sh`. The file runs with its cwd set to
a private directory, with these helpers in scope:

| Helper | Purpose |
|---|---|
| `spurfile` | reads a heredoc from stdin, writes `./Spurfile` |
| `run ARGS...` | runs the runner; fills `stdout`, `stderr` and `$status` |
| `assert_status N` | exit status |
| `assert_stdout_is` | exact match against a heredoc on stdin |
| `assert_stdout_has TEXT` / `assert_stderr_has TEXT` | fixed-string match |
| `assert_stdout_lacks TEXT` / `assert_stderr_lacks TEXT` | fixed-string absence |
| `assert_stdout_matches ERE` / `assert_stderr_matches ERE` | regex match |
| `fail MESSAGE` | abort the case with a diagnostic |

## Rules

- Strict POSIX sh. No bashisms. `shellcheck -s sh` must pass clean.
- Strict POSIX awk inside `AWK_PARSER`, and **never a single quote**: the
  program lives inside a single-quoted shell string.
- The runner depends on `sh` and `awk` only. No `mktemp`, no `stat`, no
  temporary files.
- Everything in this repository is written in English.
- Every behavior change comes with a test.
```

- [ ] **Step 5: Write the LICENSE**

`LICENSE`:

```
MIT License

Copyright (c) 2026 Esliph

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 6: Verify the documented examples**

Run:

```bash
./spur --list
sh tests/run.sh
```

Expected: the `--list` output matches the shape shown in the README, and
`44 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add Spurfile README.md CONTRIBUTING.md LICENSE
git commit -m "docs: add the Spurfile, README, CONTRIBUTING and LICENSE

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Continuous integration

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `spur` (only if shellcheck finds something)
- Modify: `tests/run.sh`, `tests/lib.sh` (same)

**Interfaces:**
- Consumes: `sh tests/run.sh`, `SPUR_TEST_SHELL`, and the `lint` task from
  Task 8.
- Produces: the third verification layer. Nothing depends on it.

- [ ] **Step 1: Write the workflow**

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
  pull_request:

jobs:
  lint:
    name: shellcheck
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck
      - name: Lint
        run: shellcheck -s sh spur tests/run.sh tests/lib.sh tests/cases/*.sh

  shells:
    name: tests (${{ matrix.shell }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shell: [sh, dash, bash]
    steps:
      - uses: actions/checkout@v4
      - name: Install shells
        run: sudo apt-get update && sudo apt-get install -y dash
      - name: Run the test suite
        run: SPUR_TEST_SHELL=${{ matrix.shell }} sh tests/run.sh

  busybox:
    name: tests (busybox ash)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run the test suite inside Alpine
        run: |
          docker run --rm -v "$PWD:/work" -w /work alpine:3.20 \
            sh -c "apk add --no-cache diffutils >/dev/null && sh tests/run.sh"
```

The Alpine job uses `docker run` from an Ubuntu runner rather than a
`container:` job, because `actions/checkout` needs a glibc Node on the
container side. `diffutils` is installed for the *harness* (`diff -u`), not
for the runner, which still depends on nothing but `sh` and `awk`.

- [ ] **Step 2: Run shellcheck locally if available**

Run: `shellcheck -s sh spur tests/run.sh tests/lib.sh tests/cases/*.sh`
Expected: no output. If `shellcheck` is not installed, skip this step — the
`lint` job covers it.

Findings to expect and how to handle them:
- `SC2086` on the `for frame in ${SPUR_STACK:-}` loop: intentional word
  splitting, already suppressed with an inline `# shellcheck disable=SC2086`.
- `SC2034` on a variable that is only read by the generated script: annotate
  with `# shellcheck disable=SC2034` and a comment saying why.
- Anything else is a real finding — fix the code, do not suppress it.

- [ ] **Step 3: Verify the Alpine job locally if Docker is available**

Run:

```bash
docker run --rm -v "$PWD:/work" -w /work alpine:3.20 \
  sh -c "apk add --no-cache diffutils >/dev/null && sh tests/run.sh"
```

Expected: `44 passed, 0 failed`. If Docker is not available locally, skip it —
CI covers it.

- [ ] **Step 4: Commit**

```bash
git add .github
git commit -m "ci: lint with shellcheck and test across the shell matrix

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Translate the existing design documents to English

**Files:**
- Modify: `docs/superpowers/specs/2026-09-21-spur-task-runner-design.md`
- Modify: `docs/superpowers/researchs/2026-09-21-make-makefile.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing. This task exists because the repository is served to the
  consumer in English, and these two files are the only Portuguese left.

- [ ] **Step 1: Translate the design document**

Translate `docs/superpowers/specs/2026-09-21-spur-task-runner-design.md` in
full, preserving its structure exactly: same headings in the same order, same
tables with the same rows, same code blocks byte for byte (the Spurfile
examples are code, not prose — only their `##` descriptions are translated).

Field names in the header block become `**Date:**`, `**Status:**`,
`**Organization:**`. Section titles become: `Summary`, `Fundamental
decisions`, `1. What comes in from make and what stays out`, `In from make`,
`In, which make does not have`, `Out — the build engine`, `Out — the
gotchas`, `2. The Spurfile language`, `Grammar`, `Properties`,
`3. Execution model`, `The assembled script`, `Shell options`, `Exit codes`,
`Exported environment`, `Working directory`, `Recursion guard`, `4. The CLI`,
`The flag cut-off rule`, `Flags`, `Spurfile discovery`, `The --list output`,
`5. Architecture, tests and distribution`, `Single file`, `Tests`, `Windows`,
`Installation`, `Known limitations`, `Out of scope for v1`,
`Validations already performed`, `Next step`.

- [ ] **Step 2: Translate the research document**

Translate `docs/superpowers/researchs/2026-09-21-make-makefile.md` in full,
with the same rule: structure and code blocks preserved, prose translated.

- [ ] **Step 3: Verify no Portuguese is left**

Run:

```bash
grep -rniE '\b(não|função|tarefa|arquivo|execução|diretório|é|são|para o|com o)\b' \
  --include='*.md' --include='*.sh' --include='*.yml' . | grep -v '^./docs/superpowers/plans/'
grep -rn '[àáâãçéêíóôõú]' --include='*.md' --include='*.sh' --include='*.yml' . \
  | grep -v '^./docs/superpowers/plans/' || echo "no accented characters left"
```

The plans directory is excluded from both greps because this plan contains
those patterns literally, in the two commands above.

Expected: the first command prints nothing; the second prints
`no accented characters left`. Also check the files with no extension:

```bash
grep -n '[àáâãçéêíóôõú]' spur Spurfile LICENSE || echo "runner and Spurfile are clean"
```

Expected: `runner and Spurfile are clean`.

- [ ] **Step 4: Commit**

```bash
git add docs
git commit -m "docs: translate the design and research documents to English

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Rename the repository and publish it

**Files:**
- No file changes. This task is git and GitHub plumbing.

**Interfaces:**
- Consumes: a finished, green repository.
- Produces: `github.com/esliph/spur`, which is the URL the README's install
  command already points at.

> **Ask before running this task.** It creates a public repository under the
> `esliph` organization and pushes to it — an outward-facing, hard-to-reverse
> action. Confirm with the user first, and confirm `gh auth status` shows an
> account with rights on `esliph`.

- [ ] **Step 1: Confirm the working tree is clean and green**

Run:

```bash
git status --short
sh tests/run.sh
```

Expected: no output from `git status`, and `44 passed, 0 failed`.

- [ ] **Step 2: Rename the local directory**

The local checkout is still called `task-runner`, the placeholder name from
before the brand was chosen. The agent cannot rename the directory it is
running in; ask the user to run, from the parent directory:

```bash
mv task-runner spur
```

Then reopen the session in the renamed directory.

- [ ] **Step 3: Create the remote and push**

Run:

```bash
gh auth status
gh repo create esliph/spur --public --source=. --remote=origin --push \
  --description "Simple Portable Universal Runner - a task runner in strict POSIX sh"
```

Expected: the command prints the new repository URL and pushes `master`.

- [ ] **Step 4: Verify the install command from the README actually works**

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/esliph/spur/master/spur | head -3
```

Expected: the first three lines of the runner. If the default branch is
`master` and the README's install URL says `main`, fix one of the two so they
agree — rename the branch with `git branch -M main && git push -u origin main`
or edit the README, and commit the change:

```bash
git add README.md
git commit -m "docs: point the install command at the default branch

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push
```

- [ ] **Step 5: Confirm CI is green**

Run: `gh run list --limit 5`
Expected: the `lint`, `shells` and `busybox` jobs all `completed success`.
