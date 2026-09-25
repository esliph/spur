## What this is

`spur` is a task runner written in strict POSIX sh. The entire program is the
single file `spur` at the repository root — there is no build step, no
compilation, no dependency install. It reads a `Spurfile`, lists tasks, and
runs one task per invocation in a single shell.

Scope boundary (enforced by design, not an oversight): **spur runs tasks, it
does not build software.** No dependency graph, no timestamp rebuilds, no
pattern rules. Requests that add a task graph or incremental builds contradict
the design of the tool.

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
`Spurfile` (`./spur test`, `./spur bench`, `./spur lint`, `./spur test-all`, `./spur check`).
Use the raw `sh tests/run.sh` form when debugging the runner itself, so a
broken runner cannot hide a broken suite.

CI (`.github/workflows/ci.yml`) runs shellcheck (pinned to 0.11.0) plus the
suite under `sh`, `dash`, `bash`, busybox ash (Alpine in Docker) and macOS
(bash 3.2, BSD awk), then under dash once per awk (`gawk --posix`, `mawk`,
`original-awk`), and runs every benchmark scenario once so none rots. Nothing is skipped locally that CI will not
catch, but `dash` catches almost everything.

## Architecture

The runner is four sequential stages inside one file, in this order:

1. **Locating** — `resolve_self` computes the runner's absolute path *before*
   any `cd`; `find_spurfile` walks up from `$PWD` looking for `Spurfile` then
   `spurfile` (both spellings exist because macOS/Windows filesystems are
   case-insensitive). The process then `cd`s to the Spurfile's directory, so
   every task runs from there.
2. **Parsing** — `AWK_PARSER`, a single awk program held in a single-quoted
   shell string, with five modes selected by `-v mode=`: `list`, `names`,
   `preamble`, `body`, `describe`. It emits diagnostics on **stdout** and carries meaning in the exit
   status (65 malformed, 67 unknown task) because `/dev/stderr` is not portable
   across awk implementations. `run_parser` must stay a function writing to the
   global `PARSER_OUT` — wrapping it in a command substitution would swallow
   the exit status the caller needs.
3. **Assembly** — `build_script` concatenates `PRELUDE` (`set -e` plus an
   injected `spur()` function pointing at `$SPUR_BIN`), then the preamble, then
   optionally `PS4`/`set -x`, then the dedented body.
4. **Execution** — `exec sh -c "$script" "spur $task" "$@"`. The single `sh -c`
   is load-bearing: it is why stdin stays free for interactive tasks, why no
   temporary file is needed, and why shell errors are labelled
   `spur build: line 3: ...` ($0 is set to `spur <task>`).

Things that follow from that structure and are easy to break:

- **The runner expands nothing.** `$VAR`, `$(cmd)`, `$$` must reach the task
  shell byte-for-byte. Any change that introduces an expansion in the parse or
  assembly path is a bug (see `tests/cases/assembly-no-expansion-by-runner.sh`).
- **Dedent** strips the longest common leading-whitespace prefix across the
  body's non-blank lines (`cprefix`), so nested `if`/`for`/heredocs keep their
  relative shape. Blank lines inside a body belong to the body; only content at
  column zero ends it.
- **Flag/argument split**: the first word not starting with `-` is the task
  name; everything after it is the task's, untouched. `spur -n test` is a dry
  run, `spur test -n` passes `-n` as `"$1"`. Short flags are deliberately not
  groupable.
- **Recursion guard**: `SPUR_STACK` is a space-separated chain exported to
  children; a task already in it exits 68. Repeated (non-recursive) calls are
  allowed — a task legitimately runs more than once without a graph.
- **Exit codes** use the sysexits range so they never collide with a task's
  own, which is propagated unchanged: 64 usage, 65 malformed Spurfile,
  66 Spurfile not found, 67 unknown task, 68 recursion.
- **Exported environment**: `SPUR_BIN`, `SPUR_ROOT` (= task working dir),
  `SPUR_INVOCATION_DIR`, `SPUR_TASK`, `SPUR_STACK`.

## Test suite

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
`SPUR_TEST_JOBS`, `SPUR_TEST_TIMES` and `SPUR_TEST_AWK` included (the chosen
awk stays first on `PATH`), so running the suite through
`./spur test` does not leak the outer invocation's state into cases.

`tests/bench/run.sh` measures the runner. It selects scenarios in
`tests/bench/` by the same rule, runs them one at a time, and prints min,
mean and max per scenario: numbers only, no baseline, no threshold. A
scenario is a straight-line script, like a case, that prepares its directory
and calls `measure ARGS...` once: one warm-up run of the runner with ARGS,
then `SPUR_BENCH_ITERATIONS` (default 10) timed runs; a failing run fails the
scenario. It needs `date +%s%N` to print nanoseconds and exits 69 when it
does not.

New cases go in `tests/cases/group-what-it-checks.sh`. The file name without `.sh`
is the case name: unique in the directory, and what `sh tests/run.sh <name>`
selects (an exact name wins over the substring filter, and a name that selects
nothing exits 64). Cases run in parallel and must be independent of one
another; the report is alphabetical, and `SPUR_TEST_JOBS=1` runs them one at
a time. The `group-` prefix keeps related cases
together and lets `sh tests/run.sh <group>-` run the whole group: `cli-`,
`discovery-` (finding the Spurfile, `-f`, `-C`), `parse-` (parsing and `list`),
`assembly-` (generated script, dry run), `exec-` (running a task), `chain-`
(`spur` called from a task), `trace-` (`-x`), `check-` (`--check`) and
`harness-` (the harness itself). Prefer `assert_stdout_is` against
`run -n <task>` when asserting on assembly — it pins the exact generated
script.

## Constraints when editing

- Strict POSIX sh. No bashisms anywhere, including in the test suite.
  `shellcheck -s sh` must pass clean; existing `# shellcheck disable=` comments
  carry a justification and new ones should too.
- Inside `AWK_PARSER`: strict POSIX awk, and **never a single quote** — the
  program lives inside a single-quoted shell string and a quote would terminate
  it.
- The runner may depend on `sh`, `awk` and the basic POSIX utilities
  `dirname`, `basename` and `cat`, nothing else; `exec-minimal-path` holds it
  to that. No `mktemp`, no `stat`, no temporary files.
- Everything in this repository is written in English, including commits and
  comments.
- Every behavior change comes with a test.
- `.gitattributes` forces LF everywhere; CRLF would break the shebang and every
  heredoc. On Windows, work through Git Bash/WSL — the tests need a POSIX shell.

## Docs

`README.md` is the user-facing contract (language, CLI, exit codes, the
make→spur mapping, and the six known limitations). Behavior changes usually
need it updated in the same commit. `CONTRIBUTING.md` holds the testing rules.
