# Coverage map

A snapshot of what the suite pins and where it is thin, audited 2026-09-21
against 48 cases. Cases get added; re-verify before acting on anything here.

## Auditing it yourself

```sh
ls tests/cases/                              # the live list; the file name is the case name
grep -rl "<behavior>" tests/cases/           # is this already pinned?
sh tests/run.sh <group>-                     # run a whole group
ls tests/cases/ | sed 's/-.*//' | sort | uniq -c   # the counts below, recomputed
```

Run that last line before quoting a count from this file. The numbers are the
part that rots first, and a wrong one here reads like coverage that exists.

To find an unreached branch in the runner, read the diagnostic strings in
`spur` (`err(...)` inside `AWK_PARSER`, and every `die`) and grep the cases for
each message. A message no case asserts is a branch no case reaches.

## What each group pins

**`cli-`** (4) — `-h`/`--help` shows usage; `-v`/`--version` matches
`spur N.N.N`; an unknown option is 64, and `-xn` is an unknown option, not
`-x -n` (short flags deliberately do not group); `-f` and `-C` without an
argument are 64.

**`discovery-`** (8) — Spurfile found in `$PWD` and by ascending search;
lowercase `spurfile` accepted, with the case tolerating case-insensitive
filesystems; nothing found is 66; `-C dir` works and a missing dir is 64;
`-f file` works and a missing file is 66 (not 64 — the codes are distinct on
purpose).

**`parse-`** (10) — `--list` output format, including column alignment,
descriptions after `##`, tasks with no description, and **file order, not
alphabetical**; `-l` lists and exits even with a task name after it; a file
with only comments prints `(no tasks defined)`; a comment at column zero
between tasks is legal; duplicate task and make-style prerequisites are both
65 with a specific message and line number; a stray line at column zero is
`syntax error: expected a task header`, including the case where that stray
line is a heredoc terminator left at column zero; an indented line after a
comment has closed a body is `indented line does not belong to any task`.

**`assembly-`** (7) — the exact generated script for a plain task, for a
dedented nested block, for a body with internal blank lines (kept) and
trailing ones (trimmed), and for a body containing a heredoc whose terminator
is indented with it; the runner expands nothing; unknown task is 67 and
suggests `spur --list`; `-n` or `-x` with no task is 64.

**`exec-`** (11) — a task runs and prints; the exit code is propagated
unchanged (42 stays 42) and never confused with a runner code; `set -e` aborts
the body; arguments after the task name pass through untouched, quoting
preserved; `SPUR_TASK`, `SPUR_ROOT`, `SPUR_INVOCATION_DIR`, `SPUR_BIN` are
exported correctly; tasks run from the Spurfile's directory, including under
`-f`; `-` and `.` are legal in task names; stdin stays free for an interactive
task; a failing command is labelled `spur <task>`; the runner works with only
`sh`, `awk`, `dirname`, `basename` and `cat` on `PATH` (`exec-minimal-path`).

**`chain-`** (5) — `spur other` inside a body works, forwards arguments, and
works when the runner was invoked by a relative path from another directory;
calling the same task twice is allowed (no graph, no dedup); mutual recursion
is 68 with the chain rendered `a -> b -> a`.

**`trace-`** (3) — `-x` traces the body with a lean `PS4`, accepting either
shell's quoting; the preamble is not traced, so preamble values do not leak to
stderr; `-n` beats `-x` (the script is printed, including `set -x`, and
nothing runs).

**`check-`** (9, added 2026-09-24) — `--check` is silent on success, reports
every task that fails `sh -n` (labelled `spur <task>:` plus a hint to run
`-n`), reports a broken preamble once and stops, checks a single named task,
is 67 for an unknown one, runs nothing (not even a `$(...)`), is 64 with `-l`,
`-n` or `-x`, and passes on an empty Spurfile. Error wording varies by shell
(busybox reports `line 0`), so the cases only pin the `spur <task>:` prefix.

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

## Confirmed gaps

Each was verified by hand: the behavior works (or fails) as described today,
and no case pins it.

### 1. `assembly-dedent-tabs` — dedent's reason for existing

`cprefix` compares leading whitespace as a *string* rather than counting
characters, specifically so mixed tabs and spaces behave. Every existing case
indents with spaces. A tab-indented body (verified working, nested block
included) would pin the behavior the design bothered to get right — and it is
the natural shape for anyone arriving from a Makefile.

### 2. `parse-crlf-spurfile` — Windows insurance

The parser strips a trailing `\r` from every line, and `.gitattributes` forces
LF precisely because CRLF would break things. No case writes a CR. A Spurfile
with CRLF line endings runs correctly today; nothing stops that from
regressing, and the people who would notice are the ones least able to debug
it.

### 3. `discovery-flag-C-with-f` — flag interaction

`-C` applies before `-f` resolves, so `spur -C sub -f custom.spur where` runs
from `sub` with `sub/custom.spur` (verified). The order is load-bearing and
untested; the two flags are only ever tested alone.

### 4. `assembly-empty-body` — a degenerate but legal shape

A task header with no indented lines assembles to prelude plus preamble and
exits 0. It is legal, it is not obviously intentional, and a parser change
could easily turn it into a 65 without anyone noticing.

### 5. `assembly-comment-ends-body`

`parse-comment-between-tasks` proves a column-zero comment does not break
`--list`, but nothing proves it *terminates the body*. `run -n` on a task
followed by a comment shows the body stopping at the comment — the actual
grammar rule, pinned where it is visible.

### 6. `exec-preamble-function` — low priority

The preamble's purpose is shared setup, and a function defined there is
callable from a body (verified). `trace-skips-preamble` defines one but never
calls it. Only a variable assignment is actually exercised end to end.

Also unpinned, and probably fine to leave: three-level recursion renders
`a -> b -> c -> a` correctly; digits and `_` in task names are allowed by the
grammar but only `-` and `.` are tested.

## Harness-level ideas

- **Keeping a failed case's directory.** `run.sh` does `rm -rf` on its work
  directory from an `EXIT` trap, so there is nothing left to inspect after a
  failure — you have to re-run the case by hand (recipe in `SKILL.md`). A
  `SPUR_TEST_KEEP=1` escape hatch that skips the cleanup and prints the path
  would pay for itself the first time a case fails only under dash. Small,
  self-contained, and it needs a `harness-` case of its own.
- **`SPUR_TEST_TMPDIR` inside the repository breaks a case.** Point it at a
  directory under the repo and `discovery-not-found` fails with
  `expected exit status 66, got 0`, because the ascending search finds the
  repository's own `Spurfile`. The failure blames the case rather than the
  setting. Either document the constraint in `CONTRIBUTING.md` or have
  `run.sh` refuse a work directory that has a `Spurfile` above it.

## Open: measuring the suite's strength

Deferred on 2026-09-25, to be designed (spec first) in a later session. The
suite has no measure of how much it would catch; these two would give it one
without adding a dependency:

- **Diagnostic coverage, automated.** The check described under "Auditing it
  yourself" (every `err("...")` in `AWK_PARSER` and every `die` message is
  asserted by some case) is still done by hand. Scripted, it would turn a new
  unasserted branch into a red run. The extraction must trim what the
  message builds at run time: a naive `die [0-9]* "[^"$]*` keeps the space
  before `$PWD` in `no Spurfile found in $PWD`, and then reports
  `discovery-not-found`, which does assert it, as a gap.
- **Light mutation testing.** A script that applies `sed` mutations to a
  copy of `spur` (flip a comparison, drop a `die`, change an exit code) and
  requires the suite to go red for each one. That is the "break the line in
  a throwaway copy" check from the skill, run for the whole file, and it
  measures the suite's strength where line coverage cannot.

Weighed against a survey of shell-testing practice and turned down, so they
need not be raised again: bats or ShellSpec (a framework, against the
zero-dependency rule), a source guard for unit tests (POSIX sh has no
`BASH_SOURCE`, and `-n`, `--list` and `--names` already expose each stage),
kcov (bash, zsh and ksh only, and blind to the awk parser), TAP or JUnit
output, and shfmt or checkbashisms (`shellcheck -s sh` and the matrix
already catch bashisms).

## The matrix (closed 2026-09-25)

The awk used to vary only by accident. It is now an axis of its own:
`SPUR_TEST_AWK` in the harness, a CI job per awk (`gawk --posix`, `mawk`,
`original-awk`) under dash, busybox awk in the Alpine job, and BSD awk with
bash 3.2 in the `macos-latest` job. Shells not yet in the matrix, if a gap
ever shows: `posh` and `mksh` (stricter than dash on some points) and
`yash`, all one `apt-get` away.

## Not worth testing

Scope is fixed by design, not by omission, and the repository is where it is
fixed — a case for anything on that list is a redesign wearing a test's
clothes, so it never appears here as a gap. The README's known limitations work
the same way: each is a decision, so a case that pins one as *current
behavior* is fine and a case that asserts the opposite is a feature request
with an assertion attached.
