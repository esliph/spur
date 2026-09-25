# Contributing

## Running the tests

```sh
sh tests/run.sh          # or: ./spur test
sh tests/run.sh discovery-flag-f   # one case, by its exact name
sh tests/run.sh parse-            # no case has that name: every case containing "parse-" (a group)
SPUR_TEST_JOBS=1 sh tests/run.sh    # one case at a time (default: one worker per CPU)
SPUR_TEST_TIMES=1 sh tests/run.sh   # each case's duration, and the five slowest
```

A name that matches no case exits with status 64 instead of reporting a green
empty run.

The harness has no dependencies: it runs the cases in parallel workers, each
in its own temporary directory under `/tmp` (override with
`SPUR_TEST_TMPDIR`) with stdin closed, and reports in alphabetical order once
they have all finished. A case writes a `Spurfile`, runs the runner, and
compares stdout, stderr and the exit status. Cases must not depend on one
another. `bats` and `shellspec` were both rejected: a tool that sells itself
as zero-dependency cannot require a framework to run its own tests.

## The shell matrix

"Strict POSIX" is a promise until a matrix makes it a fact.

```sh
SPUR_TEST_SHELL=dash sh tests/run.sh   # the strictest; if it passes here, it is POSIX
SPUR_TEST_SHELL=bash sh tests/run.sh
./spur test-all                        # every shell and awk found locally
```

The parser is an awk program, so the awk varies too. `SPUR_TEST_AWK` names
the awk the runner runs with (words split on spaces, no quoting); the harness
puts it first on `PATH`, for the runner and every `spur` a task starts:

```sh
SPUR_TEST_AWK="gawk --posix" sh tests/run.sh   # refuses gawk-only functions
SPUR_TEST_AWK=mawk sh tests/run.sh
```

CI adds busybox ash (Alpine, via Docker), macOS (bash 3.2 and BSD awk), one
job per awk (`gawk --posix`, `mawk`, `original-awk`) and `shellcheck -s sh`,
pinned to 0.11.0.

## Writing a case

Create `tests/cases/group-what-it-checks.sh`, where `group-` is the theme prefix
of its neighbours (`cli-`, `discovery-`, `parse-`, `assembly-`, `exec-`, `chain-`,
`trace-`, `check-`, `harness-`); its name, without `.sh`, is the case
name you pass to `sh tests/run.sh`, so keep it unique. The file runs with its cwd set to
a private directory, with these helpers in scope:

| Helper | Purpose |
|---|---|
| `spurfile` | reads a heredoc from stdin, writes `./Spurfile` |
| `run ARGS...` | runs the runner; fills the files `stdout` and `stderr`, the variables `$stdout` and `$stderr`, and `$status` |
| `capture CMD...` | the same for any command (the harness, a vendored copy of the runner) |
| `fake_suite` | copies the harnesses and the runner into `./fake`, with empty `tests/cases` and `tests/bench`; for `harness-` cases |
| `assert_status N` | exit status |
| `assert_stdout_is` | exact match against a heredoc on stdin |
| `assert_stdout_has TEXT` / `assert_stderr_has TEXT` | fixed-string match |
| `assert_stdout_lacks TEXT` / `assert_stderr_lacks TEXT` | fixed-string absence |
| `assert_stdout_matches ERE` / `assert_stderr_matches ERE` | regex match |
| `fail MESSAGE` | abort the case with a diagnostic |

The `has`/`lacks` assertions read `$stdout` and `$stderr`, so run commands
through `run` or `capture`. A case ends with the status of its last command:
end it with `if [ ... ]; then fail ...; fi`, never with `[ ... ] && fail`.

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

## Rules

- Strict POSIX sh. No bashisms. `shellcheck -s sh` must pass clean.
- Strict POSIX awk inside `AWK_PARSER`, and **never a single quote**: the
  program lives inside a single-quoted shell string.
- The runner depends on `sh`, `awk` and the basic POSIX utilities `dirname`,
  `basename` and `cat`, nothing else; `exec-minimal-path` holds it to that.
  No `mktemp`, no `stat`, no temporary files.
- Everything in this repository is written in English.
- Commits follow Conventional Commits, in English like the rest: a type and an
  optional scope, as in `feat(parser):` or `test:`. `git log` is the
  reference for the types already in use.
- Every behavior change comes with a test.
