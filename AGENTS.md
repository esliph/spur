# Notes for coding agents

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing anything: its
*Rules* bind every change, and it explains the test harness, the shell matrix,
the docs layout and the release process. This file adds what an agent needs
on top of it: how the runner is built and what is easy to break.

## What this is

`spur` is a task runner written in strict POSIX sh. The whole program is the
single file `spur` at the repository root: no build step, no compilation, no
dependency install. It reads a `Spurfile`, lists tasks, and runs one task per
invocation in a single shell.

Scope boundary (by design, not an oversight): **spur runs tasks, it does not
build software.** No dependency graph, no timestamp rebuilds, no pattern
rules. A request that adds a task graph or incremental builds contradicts the
design of the tool.

## Commands

```sh
sh tests/run.sh                        # full behavior suite, in parallel
sh tests/run.sh discovery-flag-f       # a single case, by its exact name
sh tests/run.sh parse-                 # no case has that name: every case containing it (a group)
SPUR_TEST_SHELL=dash sh tests/run.sh   # strictest shell; if it passes here it is POSIX
SPUR_TEST_JOBS=1 sh tests/run.sh       # one case at a time
SPUR_TEST_TIMES=1 sh tests/run.sh      # each case's duration, and the five slowest
SPUR_TEST_AWK="gawk --posix" sh tests/run.sh  # the awk the runner runs with
sh tests/bench/run.sh [name]           # benchmarks: numbers only, no baseline
shellcheck -s sh spur tests/run.sh tests/lib.sh tests/common.sh tests/bench/*.sh tests/cases/*.sh
```

The repository dogfoods itself, so the same things are available through the
`Spurfile` (`./spur test`, `./spur bench`, `./spur lint`, `./spur test-all`,
`./spur check`). Use the raw `sh tests/run.sh` form when debugging the runner
itself, so a broken runner cannot hide a broken suite. `dash` catches almost
everything CI will.

## Architecture

The runner is four sequential stages inside one file, in this order:

1. **Locating.** `resolve_self` computes the runner's absolute path *before*
   any `cd`. `find_spurfile` walks up from `$PWD` looking for `Spurfile`,
   then `spurfile`. The process then `cd`s to the Spurfile's directory, so
   every task runs from there.
2. **Parsing.** `SPUR_PARSER` is a single awk program held in a single-quoted
   shell string, with four modes selected by `-v mode=`: `list`, `names`,
   `sections`, `describe`. It writes diagnostics to **stdout** and carries
   meaning in the exit status (65 malformed, 67 unknown task), because
   `/dev/stderr` is not portable across awk implementations. `run_parser`
   must stay a function writing to the global `SPUR_PARSER_OUT`: a command
   substitution would swallow the exit status the caller needs. A run, and a
   `--check` of every task, parse the Spurfile once: `sections` emits the
   preamble and the wanted bodies in one output, split by a marker line it
   picks so that no other line starts with it
   (`assembly-separator-collision`), and `load_sections`/`next_section` take
   it apart with parameter expansion.
3. **Assembly.** `build_script` concatenates `SPUR_PRELUDE` (`set -e` plus an
   injected `spur()` function pointing at `$SPUR_BIN`), then the preamble,
   then optionally `PS4`/`set -x`, then the dedented body.
4. **Execution.** `exec sh -c "$spur_script" "spur $spur_task" "$@"`. The
   single `sh -c` is load-bearing: it keeps stdin free for interactive tasks,
   needs no temporary file, and labels shell errors `spur build: line 3: ...`
   (`$0` is `spur <task>`).

## Easy to break

- **The runner expands nothing.** `$VAR`, `$(cmd)` and `$$` must reach the
  task shell byte for byte. An expansion in the parse or assembly path is a
  bug (`tests/cases/assembly-no-expansion-by-runner.sh`).
- **Dedent** strips the longest common leading-whitespace prefix of the
  body's non-blank lines (`cprefix`), so nested `if`/`for`/heredocs keep
  their shape. Blank lines inside a body belong to it; only content at column
  zero ends it.
- **Flag/argument split.** The first word not starting with `-` is the task
  name; everything after it is the task's, untouched. Short flags are not
  groupable on purpose.
- **Recursion guard.** `SPUR_STACK` holds one frame per line: the task name,
  a space, and the physical path of its Spurfile. A task already in it *for
  the same Spurfile* exits 68. The same name in another Spurfile is another
  task, and repeated (non-recursive) calls are allowed.
- **Exit codes** stay in the sysexits range, which ordinary tools seldom
  return, apart from a task's own code, which is propagated unchanged: 64 usage, 65 malformed
  Spurfile, 66 Spurfile not found, 67 unknown task, 68 recursion.
- **Exported environment:** `SPUR_BIN`, `SPUR_ROOT` (= task working dir),
  `SPUR_INVOCATION_DIR`, `SPUR_TASK`, `SPUR_STACK`.
- **Runner variables start with `spur_` or `SPUR_`**, loop variables and
  function temporaries included (`exec-caller-environment-kept` scans the
  runner for stray names).
- **No new processes.** The runner may start `sh`, `awk` and `cat` only
  (`exec-minimal-path`).

## Where things are documented

- User-facing contract: `docs/reference.md`. A behavior change updates it in
  the same commit, and `CHANGELOG.md` under *Unreleased*.
- Design reasons and the accepted limitations: `docs/explanation.md`. A
  "missing feature" listed under *What it costs* there is a decision, not a
  gap.
- Test harness, helpers, case naming, docs layout, release: `CONTRIBUTING.md`.
- Everything in this repository is written in English, including commits and
  comments.
