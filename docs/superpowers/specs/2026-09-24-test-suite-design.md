# Test suite: parallel harness, timings, benchmarks

Status: approved design, pending implementation plan. This file lives on the
`feat/suite-test` branch only and is removed before merge.

## Goal

Make the behavior suite faster and more mature, and add a way to measure
performance, without breaking the constraints the repository already states:
strict POSIX sh, no test framework, the `sh`/`dash`/`bash`/busybox matrix,
shellcheck clean, and the `sh tests/run.sh [name|group-]` interface.

Success means:

- the suite is much faster locally, with the same isolation and the same
  readable failure output;
- the cost of each case can be seen on demand;
- there is a reproducible way to measure the runner's performance, locally,
  printing numbers only (no baseline, no comparison, no CI gate).

## Findings that shaped the design

Measured on Windows 11 + Git Bash, 81 cases:

| Measurement | Cost |
|---|---|
| whole suite | ~82 s (`sh`), ~87 s (`dash`), `sys` ~42 s |
| one runner invocation | ~500 ms |
| same, output captured in a variable instead of files | ~465 ms (noise) |
| `mkdir` + writing `stdout`/`stderr` for one case | ~50 ms |
| one `grep` assertion | ~30 ms |

Process creation dominates; file I/O does not. Replacing the capture files
with variables was considered and rejected: it saves about 5% and capturing
stdout, stderr and status separately without a file needs nested command
substitutions, which means more forks, not fewer. Files are the cheapest
capture POSIX sh offers. The real gains are parallelism and fewer forks in
the harness.

## Scope

In:

1. Parallel execution in `tests/run.sh`, on by default, with deterministic
   output.
2. Optional per-case timing.
3. A benchmark harness under `tests/bench/`.
4. `exec-minimal-path`: the runner runs with a PATH restricted to its real
   dependencies.
5. Self-tests for the harness (`harness-` group).
6. Fewer forks in `tests/run.sh` and `tests/lib.sh`.
7. Documentation, Spurfile, CI and `spur-tests` skill updates.

Out:

- Optimizing the runner itself. It becomes separate work, guided by the
  benchmarks.
- Comparing two revisions of the runner (`--against`), a stored baseline, or
  any performance threshold in CI.
- Moving cases into subdirectories or into unit/integration/e2e layers.
- Any test framework, JUnit output, or coverage tooling.

## Layout

```
tests/
├── common.sh          # new: case selection and the clock, shared by both harnesses
├── run.sh             # behavior harness
├── lib.sh             # assertion helpers
├── cases/             # unchanged: <group>-<what>.sh, flat
└── bench/
    ├── run.sh         # benchmark harness
    └── <scenario>.sh
```

## 1. Behavior harness (`tests/run.sh`)

The harness works in three phases.

**Selection.** The rule is unchanged: an exact name (`tests/cases/<arg>.sh`
exists) selects that case alone, otherwise the argument is a substring filter,
and selecting nothing prints `no test matches: <arg>` to stderr and exits 64.
The selected names are collected, in alphabetical order, before anything runs.
Names are derived with `${f##*/}` and `${n%.sh}`, with no `basename`.

**Execution.** `jobs` workers start in the background. Worker `k` (0-based)
runs, serially, every selected case whose index `i` satisfies
`i mod jobs = k`. Round-robin spreads neighbouring cases, which share a group
and a similar cost, across workers. Each case runs exactly as today: a
subshell that `cd`s into `$workdir/<name>`, sources `tests/lib.sh`, then the
case. The worker writes the case output to `$workdir/<name>.log` and the exit
status to `$workdir/<name>.status` (plus the elapsed milliseconds when timing
is on). The harness then calls `wait` once.

**Report.** The harness walks the names alphabetically, reads each status file
with the `read` builtin, and prints `ok   <name>` or `FAIL <name>` followed by
the log indented five spaces (`sed` runs only for failures). The summary
becomes:

```
81 passed, 0 failed (shell: dash, jobs: 8)
```

The `N passed, M failed` prefix is kept, since `harness-selects-by-name`
asserts on it. The exit status is 0 when nothing failed, 1 otherwise.

**Controls** (environment variables, like the existing ones):

- `SPUR_TEST_JOBS`: number of workers. Default is `getconf
  _NPROCESSORS_ONLN`, falling back to 1 if that fails or prints something
  that is not a positive integer. It is capped at the number of selected
  cases. A value set by the user that is not a positive integer prints a
  message to stderr and exits 64. `SPUR_TEST_JOBS=1` is the serial mode for
  debugging.
- `SPUR_TEST_TIMES=1`: measure each case. Each line gains its duration,
  `ok   parse-list  (412 ms)`, and the five slowest cases are listed after the
  summary. When no sub-second clock is available (see `tests/common.sh`), one
  line goes to stderr saying timings are unavailable, and the run continues
  without them.
- `SPUR_TEST_SHELL` and `SPUR_TEST_TMPDIR`: unchanged.

**Signals and cleanup.** The EXIT trap removes `$workdir`, and the INT trap
cleans up and exits 130, as today. Workers belong to the harness's process
group, so a terminal Ctrl-C reaches them too.

**Unchanged:** the `SPUR_*` unset before the loop, `$root`, `$runner` and
`$shell_under_test` as the variables a case can rely on, and the rule that
cases are independent and their order carries no meaning (now enforced in
practice).

## 2. `tests/lib.sh`

The helper contract is unchanged. Internals change to avoid forks:

- `run` still writes the `stdout` and `stderr` files, which `diff`, `fail` and
  manual debugging rely on. It then loads each file once into the variables
  `$stdout` and `$stderr` with a `while IFS= read -r` loop, which is a
  builtin. A last line without a trailing newline is kept.
- `assert_{stdout,stderr}_{has,lacks}` match with `case $var in *"$1"*)`. The
  quoted pattern is literal, so the fixed-string semantics of `grep -F` are
  kept, without a fork.
- `assert_*_matches` keeps `grep -E`, since an extended regex needs an
  external tool.
- `assert_stdout_is` keeps `cat > expected` and `diff -u`: byte-exact, with a
  readable diff.
- New helper `fake_suite`, used only by `harness-` cases: it copies
  `tests/run.sh`, `tests/lib.sh`, `tests/common.sh`, `tests/bench/run.sh` and
  `spur` into `./fake/` in the case directory, with empty `tests/cases/` and
  `tests/bench/` directories for the case to fill. The copied harness finds
  its root through `$0`, so it runs the fake suite with no new variable.

## 3. `tests/common.sh`

Sourced by both harnesses. It holds:

- `select_names DIR FILTER`: the selection rule above, applied to `DIR/*.sh`,
  setting the selected names in alphabetical order.
- Clock detection, done once: `date +%s%N` counts as a working clock when its
  output is all digits (GNU and busybox print nanoseconds; macOS prints a
  literal `N`).
- `now_ms`: the current time in milliseconds, when the clock is available.

## 4. Benchmark harness (`tests/bench/`)

**Usage.** `sh tests/bench/run.sh [name]`, with the same selection rule as the
behavior harness, including exit 64 when nothing matches.

**A scenario** is a straight-line script, like a case. It runs in its own
temporary directory with `$runner` and `$shell_under_test` available. The
setup runs once, then the scenario calls `measure`:

```sh
# tests/bench/list-500-tasks.sh
i=0
while [ $i -lt 500 ]; do
  printf 'task-%s: ## t\n  echo %s\n' $i $i
  i=$((i + 1))
done > Spurfile
measure --list
```

`measure ARGS...` runs `"$shell_under_test" "$runner" ARGS` with output
discarded: one warm-up run that is not counted, then `SPUR_BENCH_ITERATIONS`
timed runs (default 10). If any run exits non-zero, the scenario fails with
the command's stderr, since timing a broken command means nothing.

**Execution** is always serial; parallelism would contaminate the numbers.
`SPUR_TEST_SHELL` picks the shell, so shells can be compared by hand. Without
a sub-second clock the benchmark harness exits with a clear message instead of
printing false numbers.

**Output** (numbers only):

```
run-trivial        10 runs   min  478 ms   mean  502 ms   max  561 ms
list-500-tasks     10 runs   min  612 ms   mean  640 ms   max  702 ms

shell: dash, iterations: 10
```

The exit status is 0 when every scenario ran, 1 when any failed.

**Initial scenarios**, one per runner stage:

| Scenario | What it isolates |
|---|---|
| `run-trivial` | end-to-end latency of a task that echoes (the baseline) |
| `list-500-tasks` | parser scaling in `list` mode |
| `run-last-of-500` | body extraction from a large Spurfile |
| `check-500-tasks` | cost of `--check` |
| `chain-depth-5` | `spur` calling `spur` five levels deep |
| `discovery-deep` | walking up 10 directories to find the Spurfile |

## 5. New and changed cases

**`exec-minimal-path`.** Outside the shell's builtins, the runner calls
`awk`, `dirname`, `basename` and `cat` (the last one only in `usage`), plus
`sh` for the final `exec`. The case:

1. builds `./bin/` containing only `sh`, `awk`, `dirname`, `basename` and
   `cat`, copied or linked from `command -v`;
2. resolves `$shell_under_test` to an absolute path, then runs the runner
   with `PATH=$PWD/bin` through `--list`, a task, `--check` and a task that
   calls `spur other`, asserting status 0 and output each time;
3. as a negative control, removes `awk` from `./bin/` and asserts that the
   runner fails, proving the PATH restriction is in effect.

**Harness self-tests:**

| Case | What it pins |
|---|---|
| `harness-selects-by-name` | existing, unchanged |
| `harness-parallel-keeps-order` | a fake suite of about six cases with different durations produces byte-identical output with `SPUR_TEST_JOBS=4` and `SPUR_TEST_JOBS=1`, in alphabetical order |
| `harness-failure-reported` | a failing case prints `FAIL <name>` and its indented log, the others print `ok`, and the exit status is 1 |
| `harness-jobs-invalid` | `SPUR_TEST_JOBS=0` and `SPUR_TEST_JOBS=abc` exit 64 |
| `harness-times` | with `SPUR_TEST_TIMES=1`, every line ends with `(N ms)`, **or** stderr carries the clock-unavailable notice; both are accepted, as in `trace-flag` |
| `harness-cleans-workdir` | a fake suite run with `SPUR_TEST_TMPDIR` set to a directory inside the case leaves no `spur-tests.*` entry there, whether its cases pass or fail |
| `harness-bench-failing-scenario` | a scenario whose command exits non-zero makes the benchmark harness fail |
| `harness-bench-no-match` | a filter matching no scenario exits 64 |

The `harness-` cases that start a harness select only fake-suite cases or
cases that never start a harness, so the suite does not recurse.

## 6. Documentation, Spurfile, CI, skill

**The runner's dependency statement** changes everywhere it appears
(`README.md:56`, `README.md:159`, `AGENTS.md:112`, `CONTRIBUTING.md:56`) to:
the runner depends on `sh`, `awk` and the basic POSIX utilities `dirname`,
`basename` and `cat`, nothing else, and `exec-minimal-path` holds it. The
`README.md` change ships in the same commit as the case.

**AGENTS.md and CONTRIBUTING.md:** replace "cases run in alphabetical order"
with "cases run in parallel; the report is alphabetical;
`SPUR_TEST_JOBS=1` serializes". Document `SPUR_TEST_JOBS`, `SPUR_TEST_TIMES`,
`tests/common.sh`, `tests/bench/` (writing a scenario, `measure`,
`SPUR_BENCH_ITERATIONS`), `fake_suite`, and that `run` also fills `$stdout`
and `$stderr`.

**Spurfile:** a new `bench` task that passes its arguments to
`tests/bench/run.sh`, and a `lint` task (through `SOURCES`) that also covers
`tests/common.sh` and `tests/bench/*.sh`.

**CI (`.github/workflows/ci.yml`):** the shellcheck job covers the same
files as the `lint` task. A new `bench smoke` job runs
`SPUR_BENCH_ITERATIONS=1 SPUR_TEST_SHELL=dash sh tests/bench/run.sh` to keep
scenarios from rotting; it measures nothing. The shell matrix is unchanged,
and parallelism applies automatically.

**`spur-tests` skill:** update the order statement, add a short benchmark
section, fix the runner's dependency statement, and refresh
`references/coverage-map.md` with the expanded `harness-` group.

## Verification

Before calling the work done:

- the suite passes under `sh`, `dash`, `bash`, and busybox ash (Docker);
- shellcheck (Docker, same flags as CI) is clean over every shell file,
  including `tests/common.sh` and `tests/bench/*.sh`;
- the suite's wall time before and after is reported (about 82 s under `sh`
  on this machine before);
- the benchmark harness runs once locally and its output is shown;
- every new case is seen red against a deliberately broken harness or runner
  before it is trusted.
