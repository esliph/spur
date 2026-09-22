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
curl -fsSL https://raw.githubusercontent.com/esliph/spur/master/spur \
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
  body, so `if`, `for` and heredocs keep their relative shape. Indent a
  heredoc terminator with the rest of the body; the dedent puts it back at
  column zero, where the shell looks for it. Left at column zero in the
  Spurfile it ends the task instead, and the file fails to parse.
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
| `-v`, `--version` | show the version |

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
