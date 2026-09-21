# Spur — Simple Portable Universal Runner

**Date:** 2026-09-21
**Status:** Design approved, ready for the implementation plan
**Organization:** [Esliph](https://github.com/esliph)

## Summary

`spur` is a task runner written in strict POSIX sh. It reads a `Spurfile`, lists
the tasks, and runs each one in a single shell, with argument passthrough.

What sets it apart is the absence of a runtime: there is no binary to compile, and
no Go, Rust or Node to install. The program is a shell script that runs on any
Unix — including minimal Alpine containers, where `just` and Task need a binary
and `make` is not always present.

The scope is deliberately smaller than make's: **Spur is a task executor, not a
build system.** There is no dependency graph, no incremental rebuild by timestamp,
no pattern rules.

## Fundamental decisions

| Decision | Choice |
|---|---|
| Distribution | A script installed on the PATH (or copied into the repository) |
| Dialect | Strict POSIX sh — dash, ash, busybox, bash, zsh, ksh |
| Execution model | No dependencies between tasks; explicit `spur other` calls |
| Spurfile format | make-like syntax with its own parser |
| User input | Positional passthrough via `"$@"` |
| Shared state | A shell preamble at the top of the file |
| Engine | `awk` extracts the block, `sh -c` runs it |

## 1. What comes in from make and what stays out

### In from make

| Feature | Form in Spur |
|---|---|
| Named rule + recipe | `name: ## description` followed by an indented block |
| `make <target>` | `spur <task>` |
| `##` comment auto-doc | Promoted from a convention to a feature: it feeds `--list` |
| `make -n` | `spur -n` prints the assembled script instead of running it |
| `make -f` | `spur -f other.Spurfile` |
| `make -C dir` | `spur -C dir task` |

### In, which make does not have

| Feature | Reason |
|---|---|
| `"$@"` passthrough | `spur test -k foo -vv`. Impossible in make. |
| Shell preamble | Replaces variables, conditionals and `include` with a single mechanism |
| Upward search for the Spurfile | `spur test` works from any subfolder, like `git` |
| `set -e` in the block | Restores the abort-on-error that make gave through shell-per-line |
| Recursion guard | Keeps chained calls from turning into a fork bomb |
| Injected `spur` function | Chained calls work even when the runner is outside the PATH |

### Out — the build engine

| Feature | Reason |
|---|---|
| Prerequisites (`target: deps`) | Replaced by an explicit call, so that argument passthrough stays symmetric and visible |
| Incremental rebuild by timestamp | `stat` differs across GNU/BSD/busybox; `-nt` is not POSIX. The costliest feature, and the least used in a Makefile-as-task-runner |
| Parallel execution (`-j`) | Without a graph there is nothing to parallelize safely |
| Pattern rules (`%.o: %.c`) | They depend on file targets, which do not exist |
| Built-in implicit rules | Spur does not know how to compile anything, and that is what makes it predictable |
| Automatic variables (`$@`, `$<`, `$^`) | There are no prerequisites to reference. Frees `$@` for its shell meaning (the arguments) |
| `include`, conditionals (`ifeq`) | The preamble has a real `.` and a real `if` |
| Recursion via `$(MAKE)` | `spur -C sub build` is clearer |

### Out — the gotchas

| Gotcha | Replacement |
|---|---|
| Mandatory TAB | Indentation with spaces; TAB accepted, never required |
| A new shell per recipe line | The whole block in a single `sh`: `cd` and variables persist |
| `$$` to escape `$` | The runner expands nothing; `$` reaches the shell intact |
| `.PHONY` | Every task is phony by construction — the concept ceases to exist |
| `@` per line (silence) | Not implementable (see Limitations). Echo is off by default; `-x` turns it on |
| `-` per line (ignore errors) | `\|\| true` |
| Command echo by default | Off. `spur -x` turns on `set -x` with a lean `PS4` |

## 2. The Spurfile language

```sh
# Everything before the first task is the preamble: plain shell,
# injected at the top of every task that runs.
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

### Grammar

1. A line matching `^[A-Za-z0-9_.-]+:` opens a task. The body runs until the next
   line that is neither indented nor empty.
2. `## text` in the header is the description, used by `--list`. Without `##`, the
   task exists and is runnable; it just appears without a description.
3. The body is indented. Spaces are the canonical form; TAB is accepted and treated
   as indentation, never required.
4. **Dedent:** before running, the runner removes from every line of the body the
   smallest indentation common to them (empty lines do not count toward the
   calculation). This preserves the relative indentation of `if`, `for` and heredocs.
5. **Empty lines inside the body belong to the body** and do not end it. Only a line
   with content at column zero closes the task.
6. Everything before the first task is the preamble.
7. A non-indented line that does not match the task pattern and appears **after**
   the first task is a syntax error (code 65). Before the first task, it is preamble.

### Properties

- **Task names accept `-` and `.`** (`db-reset`, `docker.build`), because tasks are
  not shell functions — the body is extracted as text.
- **No expansion by the runner.** The body goes to `sh` verbatim: `$IMAGE`,
  `$(date)`, `${x:-y}`, `$$` (PID) have standard shell semantics.
- **A task without `##` is still runnable.** Documentation is not a syntactic
  requirement.

## 3. Execution model

### Pipeline for `spur test -k foo`

```
1. Parse the arguments      -> runner flags, task name, rest = "$@"
2. Locate the Spurfile      -> -f, or -C dir, or upward search
3. cd to the Spurfile root  -> deterministic cwd
4. Recursion guard          -> does SPUR_STACK contain "test"? abort
5. awk extracts             -> preamble + task body
6. Assemble the script      -> runner prelude + preamble + body
7. sh -c "$script" "spur test" -k foo
8. Propagate the exit code
```

### The assembled script

```sh
set -e                                  # runner prelude
spur() { "$SPUR_BIN" "$@"; }            # runner prelude
IMAGE=myapp:latest                      # user preamble
_log() { printf '>> %s\n' "$1"; }       # user preamble
pytest -q "$@"                          # task body
```

The form `sh -c 'code' name arg1 arg2` sets `$0=name` and `$1=arg1` natively, as
POSIX specifies. The consequences, all verified:

- **stdin stays free** — `spur psql`, `spur shell` and `docker run -it` work. A pipe
  (`echo "$body" | sh -s`) would hijack stdin and break every interactive task.
- **No temporary file** — no `mktemp` (which is not POSIX), no cleanup `trap`, no
  residue on Ctrl-C, no failure mode on a full or read-only `/tmp`.
- **Isolation** — `exit 1` in the task does not kill the runner; `set -e` in the task
  does not contaminate the runner.
- **`$0` becomes an error label** — the shell reports `spur build: line 3: ...`.

### Shell options

`set -e` on, `set -u` off, and `pipefail` does not exist in POSIX.

`set -e` restores what make gave for free: with one shell per line, a failing
command aborted the recipe; with the whole block in one shell, we have to turn it
back on.

`set -u` is too opinionated to impose — it would turn a missing `$1` into a raw
error, instead of letting the task write `${1:?specify the environment}`. Whoever
wants it puts it in the preamble.

### Exit codes

The task propagates its own code **intact** — CI depends on it. Runner errors use
the 64+ range (the `sysexits` convention), so they never collide with a task's code.

| Code | Meaning |
|---|---|
| *(the task's)* | Propagated unchanged |
| 64 | Incorrect usage (invalid flag, no task given) |
| 65 | Malformed Spurfile |
| 66 | Spurfile not found |
| 67 | Unknown task |
| 68 | Recursion detected |

### Exported environment

| Variable | Contents |
|---|---|
| `SPUR_BIN` | Absolute path of the runner; this is what makes the injected `spur` function work outside the PATH |
| `SPUR_ROOT` | The Spurfile's root (= the task's cwd) |
| `SPUR_INVOCATION_DIR` | The folder the user called from |
| `SPUR_TASK` | Name of the running task |
| `SPUR_STACK` | The call stack, for the recursion guard |

### Working directory

Every task runs in the **directory that holds the Spurfile in use**, regardless of
where it was invoked from. `SPUR_INVOCATION_DIR` preserves the original folder for
whoever needs it.

Without this, `spur test` would give different results depending on the folder it
was called from, and the upward search would become a trap instead of a convenience.

The rule holds for every way of locating the file, and `-C` is applied before
anything else:

| Invocation | `SPUR_ROOT` (= the task's cwd) |
|---|---|
| `spur test` (upward search) | The directory where the Spurfile was found |
| `spur -f ../other/Spurfile test` | `../other/` — the folder of the file pointed at |
| `spur -C api test` | `api/`, or the ancestor of `api/` where the Spurfile is found |
| `spur -C api -f custom.spur test` | `api/`, where `custom.spur` is resolved |

### Recursion guard

Tasks call tasks through subprocesses (`spur deps` inside a body), so cycle
detection has to cross process boundaries. `SPUR_STACK` is exported and accumulates
the chain; on entering a task, the runner tests whether the name is already on the
stack:

```sh
case " ${SPUR_STACK:-} " in
  *" $task "*) die 68 "recursion detected: ${SPUR_STACK# } -> $task" ;;
esac
```

It detects only **ancestors**. A task called twice in sequence (not nested) is
allowed, which is the correct behavior.

## 4. The CLI

```
spur [runner flags] <task> [task arguments...]
```

### The flag cut-off rule

**The first word that does not start with `-` is the task name. Everything after it
belongs to the task, untouched.**

```sh
spur -n test          # -n is the runner's (dry run of 'test')
spur test -n          # -n is the task's, arrives as "$1"
spur -C api test -k x # -C api is the runner's; -k x is the task's
```

Without this rule, every new flag Spur gained would steal a name from the tasks'
flag space. Since the runner never looks at anything after the task name, the set
of flags can grow without breaking any Spurfile.

### Flags

| Flag | Effect |
|---|---|
| `-f FILE` | Use another Spurfile (turns off the upward search) |
| `-C DIR` | `cd DIR` before anything else |
| `-l`, `--list` | List the tasks and exit |
| `-n` | Print the assembled script instead of running it |
| `-x` | Turn on `set -x` after the preamble, with `PS4='$ '` |
| `-h`, `--help` | Help |
| `-V`, `--version` | Version |

`PS4` is fixed at `'$ '` so that the echo comes out as `$ docker build -t app .`,
instead of the shell's default `+ `. The `set -x` line is inserted **after** the
preamble, so that variable assignments and function definitions do not pollute the
output.

**Precedence:** `-n` beats `-x`. With both flags, the script is printed (already
containing the `set -x` line) and nothing is run.

There is no grouping of short flags (`-xn`): the parsing is a twenty-line
`while`/`case`, and the gain does not pay for the complexity.

### Spurfile discovery

It looks for `Spurfile`, then `spurfile`, in the current directory; if it finds
neither, it goes up one level and repeats, up to `/`.

Both spellings exist because macOS and Windows have *case-insensitive* filesystems,
where `Spurfile` and `spurfile` are the same file, while Linux tells them apart. The
search going up to `/` may, from a directory with no project, reach a Spurfile in
`$HOME` — the same risk `git` and `just` accept, and `--list` and the error
messages always show the resolved path, which makes the surprise diagnosable.

### The `--list` output

```
$ spur --list
Spurfile: /home/dan/project/Spurfile

  build      build the image
  test       run the tests
  db-reset   recreate the database (destructive)
  deploy
```

Tasks in **file order**, not alphabetical: the order in which they were written
carries intent (main flow first, utilities after).

`spur` with no argument at all does exactly this — a deliberate divergence from
make, which would run the first target.

## 5. Architecture, tests and distribution

### Single file

`spur` is **one** script, with the `awk` embedded as a string. The alternative —
`spur` + `resolve.awk` side by side — would force the runner to find out where its
own `.awk` lives, across symlinks, a relative `$0` and an install in
`/usr/local/bin`.

Estimate: 200-300 lines, organized into functions (`parse_args`, `find_spurfile`,
`extract_task`, `list_tasks`, `run_task`, `die`). No build step: the file in the
repository is the file that gets installed.

```
spur/
├── spur            # the runner
├── Spurfile        # dogfooding: the project uses itself
├── tests/
│   ├── run.sh      # harness
│   └── cases/
├── docs/superpowers/
└── README.md
```

The local repository is currently called `task-runner`, a provisional name from
before the brand was chosen. Renaming it to `spur` (and publishing it as
`esliph/spur`) is part of the implementation plan.

The `Spurfile` at the root is not decoration: if the project's own `spur lint` and
`spur test` are uncomfortable to write, the design is wrong and that shows up in
the first week.

### Tests

**Behavior tests.** A plain-sh harness: each case builds a temporary Spurfile,
invokes `spur` and compares stdout, stderr and the exit code. Chosen over `bats`
(requires bash) or `shellspec` (one more dependency to install) because the tool
sells itself as zero-dependency, and requiring a framework to run its tests would
contradict that on the first line of CONTRIBUTING. Accepted cost: no pretty diffs
and no `--filter` out of the box. Harness estimate: ~60 lines.

**Shell matrix.** This is what turns "strict POSIX" from a promise into a verified fact:

| Shell | Role |
|---|---|
| `dash` | The strictest. If it passes here, it is truly POSIX |
| `bash` | The one most people use day to day |
| `busybox ash` | Alpine and minimal containers, via Docker in CI |
| Git Bash | The author's development environment |

`dash` and `bash` are already available in the development environment, which lets
the portability check run locally, not only in CI.

**`shellcheck -s sh`** in CI, as a third layer: it catches bashisms statically,
before they become a runtime bug on an Alpine in production.

### Windows

**`spur` requires a POSIX shell. On Windows that means Git Bash, MSYS2, WSL or
Cygwin. There will be no native version for cmd or PowerShell.**

That is exactly `make`'s requirement, so it is not a regression — but the README
has to be precise about what it promises. "Portability" here means *runs on any
Unix, under any POSIX shell, with no runtime to install*. It does not mean *runs
natively everywhere*. `just` and Task, being compiled, cover native Windows better;
Spur wins where they lose — inside an Alpine container, on a machine with no
toolchain, on a server where binaries cannot be installed.

### Installation

```sh
curl -fsSL https://raw.githubusercontent.com/esliph/spur/main/spur \
  -o ~/.local/bin/spur && chmod +x ~/.local/bin/spur
```

And the *vendored* mode: copy `spur` into the repository and commit it. Whoever
clones runs `./spur test` without installing anything, and the injected `spur`
function makes chained calls work in this mode too. Packaging (brew, apt) is out of
scope for v1.

## Known limitations

Recorded here deliberately, as accepted consequences of the design:

1. **Tasks can run more than once.** With no graph there is no dedup: if `build`
   calls `deps` and `lint` also calls `deps`, `deps` runs twice. That is the price
   of the explicit call, and the gain is that argument passthrough stays symmetric
   and visible in the task body.

2. **`-n` does not expand the call chain.** It shows the assembled script of the
   requested task and only that. `spur deps` inside the body only happens at run
   time, and discovering it statically would require interpreting the shell.
   `make -n` does better, because it knows the graph before running. It was decided
   not to include a heuristic (grep for lines that start with `spur `): a dry run
   that is right 80% of the time is worse than one that honestly declares its scope.

3. **make's per-line `@` is not implementable.** make can do it because it fires one
   line at a time; Spur hands the whole block to one `sh` and does not know where
   each command starts and ends — there are `if`, `for`, pipes and line
   continuations. Implementing it would require parsing shell inside awk. The
   substitutes are `spur -x` (the whole invocation) and `{ set +x; } 2>/dev/null`
   … `set -x` (a stretch of the block). The redirection is needed because a bare
   `set +x` echoes itself before turning off.

4. **The preamble runs for every task.** Irrelevant if it is cheap (assignments,
   `.env`, functions); costly if someone puts heavy work there. Worth documenting in
   the README.

5. **No native Windows.** See the Windows section.

## Out of scope for v1

- Private tasks by `_` prefix (omitted from `--list`). Without prerequisites, almost
  every natural helper becomes a function in the preamble; the remaining case is the
  helper that needs to run in an isolated subprocess. Add it if the pain shows up.
- Packaging in brew, apt or similar.
- Grouping of short flags (`-xn`).
- Parallel execution, timestamps, pattern rules — outside the scope of the product,
  not just of v1.

## Validations already performed

The following primitives were tested during the design, in Git Bash with `dash` and
`bash` available:

- `sh -c 'code' name arg1 arg2` sets `$0` and the positionals as POSIX specifies.
- A custom `PS4` with `set -x` turned on after the preamble produces a readable
  echo, with values **already expanded** (`echo 'building myapp:latest'`, not
  `$IMAGE`).
- A bare `set +x` echoes itself; `{ set +x; } 2>/dev/null` solves it.
- `set -e` inside `sh -c` aborts and propagates the code correctly.
- stdin stays free under `sh -c`, allowing interactive tasks.
- The recursion guard via an environment variable crosses processes and detects
  `a -> b -> a`, returning its own code.
- The injected `spur` function makes chained calls work with the runner invoked by
  a relative path, from another directory, outside the PATH.
- Arguments are passed through correctly in chained calls
  (`spur lint --fix` inside a body).

## Next step

Implementation plan via the `superpowers:writing-plans` skill, with TDD.
