# Contributing

spur is one file, `spur`, at the root of the repository. There is no build
step and nothing to install: you need a POSIX shell, `awk`, and
`shellcheck` 0.11.0 for the lint. On Windows, work in Git Bash or WSL.

## Before you open a pull request

```sh
./spur check   # spur --check, shellcheck, and the test suite
```

Also run the suite under dash, the strictest shell
(`SPUR_TEST_SHELL=dash sh tests/run.sh`), and read [Rules](#rules).

## Running the tests

```sh
sh tests/run.sh                    # every case, in parallel; or: ./spur test
sh tests/run.sh discovery-flag-f   # one case, by its exact name
sh tests/run.sh parse-             # no case has that name: every case containing "parse-" (a group)
SPUR_TEST_JOBS=1 sh tests/run.sh   # one case at a time (default: one worker per CPU)
SPUR_TEST_TIMES=1 sh tests/run.sh  # each case's duration, and the five slowest
```

A name that matches no case exits 64 instead of reporting a green empty run.

The harness has no dependencies. It runs each case in a parallel worker, in
its own temporary directory under `/tmp` (set `SPUR_TEST_TMPDIR` to change
it), with stdin closed. It reports in alphabetical order once every case has
finished, so the output does not depend on the number of workers. A case
writes a `Spurfile`, runs the runner, and compares stdout, stderr and the
exit status. Cases must not depend on one another.

`run.sh` unsets every `SPUR_*` variable before the cases run, its own
included, so `./spur test` does not leak the outer run into the cases.

`bats` and `shellspec` were both rejected: a tool that sells itself as
zero-dependency cannot need a framework to test itself. When debugging the
harness itself, use `sh tests/run.sh` rather than `./spur test`, so a broken
runner cannot hide a broken suite.

## The shell matrix

"Strict POSIX" is a promise until a matrix makes it a fact.

```sh
SPUR_TEST_SHELL=dash sh tests/run.sh   # the strictest; if it passes here, it is POSIX
SPUR_TEST_SHELL=bash sh tests/run.sh
./spur test-all                        # every shell and awk found locally
```

The parser is an awk program, so the awk varies too. `SPUR_TEST_AWK` names
the awk the runner runs with (words split on spaces, no quoting). The harness
puts it first on `PATH`, for the runner and for every `spur` a task starts:

```sh
SPUR_TEST_AWK="gawk --posix" sh tests/run.sh   # refuses gawk-only functions
SPUR_TEST_AWK=mawk sh tests/run.sh
```

CI (`.github/workflows/ci.yml`) runs `shellcheck -s sh` pinned to 0.11.0,
and the suite under `sh`, `dash`, `bash`, busybox ash (Alpine, in Docker) and
macOS (bash 3.2 and BSD awk). It then runs the suite under dash once per awk
(`gawk --posix`, `mawk`, `original-awk`) and every benchmark scenario once.

## Writing a case

Create `tests/cases/group-what-it-checks.sh`. The file name without `.sh` is
the case name: it must be unique, and it is what `sh tests/run.sh <name>`
selects. `group-` is the prefix of its neighbours:

| Prefix | Covers |
| --- | --- |
| `cli-` | flags, help, version, suggestions |
| `discovery-` | finding the Spurfile, `-f`, `-C` |
| `parse-` | parsing and `--list` |
| `assembly-` | the generated script, dry run |
| `exec-` | running a task |
| `chain-` | `spur` called from a task |
| `trace-` | `-x` |
| `check-` | `--check` |
| `harness-` | the harness itself |

The case runs with its working directory set to a private directory, with
these helpers in scope (from `tests/lib.sh`):

| Helper | Purpose |
| --- | --- |
| `spurfile` | reads a heredoc from stdin, writes `./Spurfile` |
| `run ARGS...` | runs the runner; fills the files `stdout` and `stderr`, the variables `$stdout` and `$stderr`, and `$status` |
| `capture CMD...` | the same for any command (the harness, a vendored copy of the runner) |
| `fake_suite` | copies the harnesses and the runner into `./fake`, with empty `tests/cases` and `tests/bench`; for `harness-` cases |
| `wait_for FILE [SECONDS]` | polls once a second until FILE exists (default 20 s); fails with 1 when it never does |
| `assert_status N` | exit status |
| `assert_stdout_is` | exact match against a heredoc on stdin |
| `assert_stdout_has TEXT` / `assert_stderr_has TEXT` | fixed-string match |
| `assert_stdout_lacks TEXT` / `assert_stderr_lacks TEXT` | fixed-string absence |
| `assert_stdout_matches ERE` / `assert_stderr_matches ERE` | regex match |
| `fail MESSAGE` | abort the case with a diagnostic |

- The `has`/`lacks` assertions read `$stdout` and `$stderr`, so run commands
  through `run` or `capture`.
- To assert on assembly, prefer `assert_stdout_is` against `run -n <task>`:
  it pins the exact generated script.
- A case ends with the status of its last command. End it with
  `if [ ... ]; then fail ...; fi`, never with `[ ... ] && fail`.

## Benchmarks

```sh
sh tests/bench/run.sh              # or: ./spur bench
sh tests/bench/run.sh run-         # a filter, as for the tests
SPUR_BENCH_ITERATIONS=30 SPUR_TEST_SHELL=dash sh tests/bench/run.sh
```

The benchmark harness prints min, mean and max per scenario: numbers only,
with no baseline and no comparison. Compare shells or revisions by hand. It
needs `date +%s%N` to print nanoseconds (GNU date does; macOS and busybox in
Alpine do not) and exits 69 otherwise.

A scenario is `tests/bench/<name>.sh`: a straight-line script that runs in
its own temporary directory, prepares what it needs, and calls
`measure ARGS...` once. `measure` runs the runner with ARGS once to warm up,
then `SPUR_BENCH_ITERATIONS` times (default 10), timed, with output
discarded. If any run fails, the scenario fails with the runner's stderr.

## Documentation

The user documentation follows [Diátaxis](https://diataxis.fr/): each page
has one job.

| File | Holds |
| --- | --- |
| `README.md` | what spur is, an example, install, and links to the rest |
| `docs/tutorial.md` | a first Spurfile, step by step, for a new user |
| `docs/how-to.md` | recipes for specific jobs |
| `docs/reference.md` | the contract: syntax, flags, environment, exit codes |
| `docs/explanation.md` | the design, its reasons and its costs |
| `CHANGELOG.md` | what each version changed; the source of the release notes |

A behavior change updates `docs/reference.md` in the same commit, plus any
other page that shows the changed behavior. A user-visible change also goes
into `CHANGELOG.md`, under *Unreleased*.

Two lines are read by tools, so keep their exact form:

- `README.md` shows `spur -v` output on a line of its own, `spur X.Y.Z`.
  `spur release` rewrites that line, and `cli-version-matches-readme` fails
  when it differs from `spur -v`.
- Each version in `CHANGELOG.md` is a `## [X.Y.Z] - YYYY-MM-DD` heading with
  a `[X.Y.Z]: ` link at the end of the file. `spur release-notes` reads both.

Copy command output into the docs from a real run, not from memory.

## Releasing

A release takes two steps. First, on `develop`, clean and pushed:

```sh
./spur release 0.3.0
```

`spur release` refuses:

- a version that is not `X.Y.Z` or does not follow the current one;
- a branch other than `develop`, uncommitted changes, or a `develop` that
  differs from `origin/develop`;
- a version already tagged;
- an empty *Unreleased* section.

Then it runs `spur --check`, sets the version in `spur` and in the README,
turns *Unreleased* into `## [0.3.0] - <today>` with its compare link, commits
`chore(release): 0.3.0`, pushes `develop`, and opens the pull request into
`master` with the release notes as its body. It prints a line before each
step. It does not run lint or the tests: CI runs both on the pull request,
and nothing is published until they pass on `master`.
`spur release-notes 0.3.0` prints those notes on their own.

Second, merge that pull request. On `master`, once every CI job is green, the
`release` job runs `spur publish`. It tags the merge commit `v0.3.0` and
publishes the GitHub release, with the runner as its asset and the notes as
its body. A push to `master` whose version is already tagged publishes
nothing.

## Rules

- **Scope.** spur runs tasks; it does not build software. A change that adds
  a task graph, incremental builds or pattern rules will be turned down.
- **Strict POSIX sh**, in the runner and in the test suite. No bashisms.
  `shellcheck -s sh` must pass clean. A new `# shellcheck disable=` comment
  carries a justification, like the existing ones.
- **Strict POSIX awk inside `SPUR_PARSER`**, and never a single quote: the
  program lives inside a single-quoted shell string.
- **The runner depends on `sh`, `awk` and `cat`, nothing else.**
  `exec-minimal-path` holds it to that. No `mktemp`, no `stat`, no temporary
  files. Split paths with parameter expansion, not `dirname` or `basename`:
  every process the runner starts is paid on every run, and again by every
  `spur` a task calls.
- **The runner expands nothing.** An expansion in the parse or assembly path
  is a bug (`assembly-no-expansion-by-runner`).
- **The runner's variables start with `spur_` or `SPUR_`**, loop variables
  and function temporaries included. The task inherits the runner's
  environment, so any other name would overwrite one the caller exported
  (`exec-caller-environment-kept` scans for that).
- **Every behavior change comes with a test.**
- **LF line endings.** `.gitattributes` forces them; CRLF breaks the shebang
  and every heredoc.
- **English** everywhere: code, comments, docs and commits.
- **Conventional Commits**: a type and an optional scope, as in
  `feat(parser):` or `test:`. `git log` shows the types already in use.
