# Changelog

Every release of spur, newest first, in the format of
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). spur follows
[Semantic Versioning](https://semver.org/).

What is merged but not released yet goes under *Unreleased*. `spur release
X.Y.Z` dates that section, and the release page on GitHub is this file's
section for the version, with the install instructions added.

## [Unreleased]

## [0.3.1] - 2026-09-30

### Fixed

- The recursion guard tells tasks apart by their Spurfile as well as their name: `install` calling `spur -C sub install` no longer exits 68, while a real recursion is still caught across Spurfiles and through a symlinked directory. `SPUR_STACK` now holds one frame per line, the task name and the physical path of its Spurfile.

## [0.3.0] - 2026-09-30

### Changed

- The runner no longer uses `dirname` or `basename`: it depends on `sh`, `awk` and `cat`, nothing else, and `exec-minimal-path` runs it with only those three on `PATH`. Paths are split with parameter expansion, which removes about ten processes from every run.
- A run parses the Spurfile once instead of twice, and `--check` once instead of once per task plus two. Under dash on Windows, a trivial run went from 205 to 99 ms and `--check` of 50 tasks from 4.5 to 1.9 s.

### Added

- `CHANGELOG.md`, the source of the release notes, and a release process: `spur release X.Y.Z` prepares the release pull request, and merging it into `master` tags and publishes the version once CI is green.

## [0.2.0] - 2026-09-28

New ways to read a Spurfile without running it, sections in `spur list`, and a round of fixes from the branch review. The runner is still one file that depends on `sh`, `awk`, `dirname`, `basename` and `cat`, and nothing else — now pinned by a test. Everything here landed in #2.

### Added

- `##@ Title` lines group the tasks that follow into sections in `spur list`.
- `--check` syntax-checks every task, or just one (`spur --check deploy`), without running anything, and reports what is malformed, including a heredoc that is never terminated.
- `--names` prints the bare task names, one per line, for scripts and shell completion.
- `spur --describe <task>` prints a task's long help (its `##` block).
- An unknown task suggests the closest task names, and suggests no unrelated name for a short one.

### Fixed

- `SPUR_BIN` resolves to `./spur` when the runner is started as `sh spur`.
- `-f` and `-C` are kept in the hints printed after an error, so the suggested command works as printed.
- `###` lines stay out of a task's long help.
- The caller's environment is no longer overwritten by the runner's own variables: every runner variable is now prefixed `spur_` or `SPUR_`, and `exec-caller-environment-kept` scans the runner to keep it that way.
- `--check` parses the preamble once and assembles without subshells.

### Tests, benchmarks and CI

- `tests/run.sh` runs the cases in parallel workers (`SPUR_TEST_JOBS`, default the number of CPUs) and reports in alphabetical order. `SPUR_TEST_TIMES=1` times each case and lists the five slowest, `SPUR_TEST_AWK` chooses the awk the runner runs with, and Ctrl-C or TERM stops the workers cleanly, a second signal included under bash 3.2.
- A benchmark harness, `tests/bench/run.sh`, with six scenarios. It prints min, mean and max per scenario, with no baseline and no threshold.
- The suite grew from 48 to 114 cases, adding tab dedent, CRLF, `-C` with `-f`, empty bodies, nearest-Spurfile discovery, multi-line preambles, digits and underscore in task names, and `exec-minimal-path`.
- CI pins shellcheck to 0.11.0, adds macOS (bash 3.2, BSD awk), runs the suite under dash once per awk (`gawk --posix`, `mawk`, `original-awk`) and runs every benchmark once.

## [0.1.0] - 2026-09-22

First release. `spur` reads a `Spurfile`, lists the tasks and runs one per invocation in a single shell. The whole program is one file that depends on `sh` and `awk`: no build step and no runtime to install.

The scope is deliberate: spur runs tasks, it does not build software — no dependency graph, no timestamp rebuilds, no pattern rules. It needs a POSIX shell, so on Windows it runs under Git Bash, MSYS2, WSL or Cygwin. The trade-offs that follow are listed in the README under *What it costs*.

### Added

- The `Spurfile` language: a line matching `^[A-Za-z0-9_.-]+:` opens a task, `## text` in the header documents it for `--list`, and the indented body is
  dedented before it runs, so `if`, `for` and heredocs keep their relative shape. Everything before the first task is the preamble, injected at the top of every task that runs.
- One shell for the whole body, with `set -e` on: `cd` persists, variables persist, and stdin stays free, so interactive tasks work.
- A body that reaches the shell byte for byte. The runner expands nothing, so `$IMAGE`, `$(date)`, `${x:-y}` and `$$` arrive intact and there is no template layer to escape.
- Positional passthrough: `spur test -k login -vv` hands `-k login -vv` to the body as `"$@"`. The first word that does not start with `-` is the task name; everything after it belongs to the task.
- Spurfile discovery: `Spurfile`, then `spurfile`, in the current directory and then upwards to `/`. Every task runs in the directory that holds the file in use.
- Chained calls: the assembled script injects a `spur` function pointing at the runner itself. A recursion guard over `SPUR_STACK` exits 68, while repeated non-recursive calls are allowed.
- Runner flags: `-f FILE`, `-C DIR`, `-l`/`--list`, `-n` (print the assembled script instead of running it), `-x` (trace with `PS4='$ '`, after the preamble), `-h`/`--help` and `-v`/`--version`. Short flags cannot be grouped.
- Exit codes in the `sysexits` range, so they never collide with a task's own, which is propagated unchanged: 64 usage, 65 malformed Spurfile, 66 Spurfile not found, 67 unknown task, 68 recursion.
- Exported environment: `SPUR_BIN`, `SPUR_ROOT`, `SPUR_INVOCATION_DIR`, `SPUR_TASK` and `SPUR_STACK`.
- Shell diagnostics labelled `spur <task>: line N: ...`, from `$0` on the single `sh -c` that runs the task.
- Documentation: `README.md` as the user-facing contract (the language, the CLI, the exit codes, the make → spur mapping and the known limitations), `CONTRIBUTING.md` for the testing rules, and an MIT `LICENSE`.
- A behavior suite of 48 cases under `tests/`, run by a dependency-free harness, plus CI running `shellcheck -s sh` and the suite under `sh`, `dash`, `bash` and busybox `ash`. Green on this tag.

[Unreleased]: https://github.com/esliph/spur/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/esliph/spur/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/esliph/spur/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/esliph/spur/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/esliph/spur/releases/tag/v0.1.0
