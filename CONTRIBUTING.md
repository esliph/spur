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
