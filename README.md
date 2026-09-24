# spur

**Simple Portable Universal Runner** — a task runner in strict POSIX sh.

`spur` reads a `Spurfile`, lists the tasks, and runs each one in a single
shell with positional argument passthrough. There is nothing to compile and
no runtime to install: it is one shell script that runs on any Unix.

The scope is deliberately smaller than make's: **spur runs tasks, it does not
build software.** No dependency graph, no timestamp-based rebuilds, no
pattern rules.

## Why spur exists

### The problem

`make` is a build system that most projects use as a task runner. Once every
target is `.PHONY`, its engine — the timestamp graph, the pattern rules, the
built-in recipes for compiling C — is dead weight, while its gotchas are
still fully alive: the mandatory TAB, a separate shell for every recipe line
so `cd` does not persist,  `$$` to get a literal `$` through to the shell, and
a different dialect on BSD than on GNU.

The modern answers to that — `just`, Task — fix the gotchas, and charge for
it in a currency make never asked for: a compiled binary. On a laptop that is
one `brew install`. In a CI image, an Alpine container, a locked-down server
or a machine with no toolchain, it is a download per architecture, a
checksum, a version to pin, and one more thing that can be missing at the
moment you need it.

spur takes the third route. It keeps make's shape — a file of named recipes
at the root of the repository, run as `spur test` — throws the build engine
away instead of working around it, and ships as a single sh script, so there
is nothing left to install.

### Against the alternatives


|                        | make                    | just                  | Task                        | spur                          |
| ---------------------- | ----------------------- | --------------------- | --------------------------- | ----------------------------- |
| Runtime to install     | usually already present | a binary per platform | a binary per platform       | none: `sh` and `awk`          |
| In a minimal container | not always there        | fetch the right arch  | fetch the right arch        | runs on what is already there |
| What it is             | a build system          | a task runner         | a task runner               | a task runner                 |
| Dependency graph       | yes, by timestamp       | yes, ordering         | yes, plus up-to-date checks | none, by design               |
| Argument passthrough   | none; use a variable    | declared parameters   | variables on the CLI        | `"$@"`, verbatim              |
| Native Windows         | no                      | yes                   | yes                         | no                            |


`just` and Task are better tools than spur wherever a binary is not a
problem: they are faster, they have real parameters, and they run natively on
Windows. spur wins in exactly one place, and it is a place a lot of work
happens — a container or a server where you would rather add nothing at all.

### What is actually different

- **Nothing to install.** The runner is one file that depends on `sh` and
`awk`. Fetch it with `curl`, or commit it into the repository and let
whoever clones run `./spur test` on a machine with no package manager and
no network.
- **Positional passthrough.** `spur test -k login -vv` hands `-k login -vv`
to the body as `"$@"`. make has nothing for this; the usual workarounds are
a variable (`make test ARGS='-k login'`) or a wrapper script. It is the
single feature most often missing when a Makefile is used as a task runner.
- **One shell for the whole task.** The body is an ordinary shell block, not
a dialect: `cd` persists, variables persist, `if` and `for` and heredocs
work the way they do in a script, and `set -e` aborts on the first failure.
- **The runner expands nothing.** `$IMAGE`, `$(date)`, `${x:-y}` and `$$`
reach the shell byte for byte. There is no template layer to escape, so
there is nothing to learn beyond the shell you already know.
- **A scope you can read in an afternoon.** About 330 lines of sh with the
parser included. When it does something surprising, the source is right
there and it is the same file that was installed.

### What it costs

These are consequences of the design, accepted deliberately, not a backlog:

1. **A task can run more than once.** With no graph there is no dedup: if
 `build` calls `deps` and `lint` calls `deps`, `deps` runs twice. That is
 the price of explicit calls, and the gain is that argument passthrough
 stays symmetric and visible in the body.
2. **No parallelism and no incremental rebuild.** Both need a dependency
 graph, and `-j`, timestamps and pattern rules are out of the product's
 scope, not just of this version. If you are compiling software, you want
 make or CMake, and spur is happy to be the thing that calls them.
3. **`-n` does not expand the call chain.** The dry run shows the assembled
 script of the task you asked for, and only that. A `spur deps` inside a
 body happens at run time, and discovering it statically would mean
 interpreting shell.
4. **make's per-line `@` is not implementable.** make dispatches one line at
 a time; spur hands the whole block to one `sh` and does not know where
 each command begins. Use `spur -x` to trace the whole invocation, or
 `{ set +x; } 2>/dev/null` … `set -x` for a stretch of the body (the
 redirection is needed because a bare `set +x` echoes itself before
 turning off).
5. **The preamble runs for every task.** Irrelevant when it is cheap
 (assignments, `.env`, functions); costly if you put real work there.
6. **No native Windows.** spur needs a POSIX shell: Git Bash, MSYS2, WSL or
 Cygwin. That is make's requirement too, so it is not a regression.
 "Portable" here means *runs on any Unix, under any POSIX shell, with no
 runtime installed* — not *runs natively everywhere*.
7. **Chained calls do not inherit `-f`.** Inside a body, `spur other` finds
 the Spurfile by the usual upward search from `SPUR_ROOT`. Propagating `-f`
 would break `spur -C sub build` in a body.

## Install

There are two ways to get spur, and they answer different questions. Install
it **globally** to have `spur` on your own machine for every project you
touch. Vendor it **locally** into a repository so that anyone who clones it
— a colleague, a CI runner, a container — has the runner already, with
nothing to fetch. They are independent, and a project that vendors spur is
still perfectly usable by someone who has it installed globally.

### Globally, for your user

Drop the file somewhere on your `PATH` and make it executable. `master` is
the tip of development and the ref every tag is cut from:

```sh
curl -fsSL https://raw.githubusercontent.com/esliph/spur/master/spur \
  -o ~/.local/bin/spur && chmod +x ~/.local/bin/spur
```

A specific version: the URL takes any git ref, so put a tag from [the tag
list](https://github.com/esliph/spur/tags) in place of `<tag>`.

```sh
curl -fsSL https://raw.githubusercontent.com/esliph/spur/<tag>/spur \
  -o ~/.local/bin/spur && chmod +x ~/.local/bin/spur
```

`~/.local/bin` is a convention, not a requirement — any directory on your
`PATH` works, and if it is not on yours yet, add it (`export PATH="$HOME/.local/bin:$PATH"` in your shell's rc file). Check the result:

```sh
$ spur -v
spur 0.1.0
```

Upgrading is the same command with another ref, and uninstalling is
`rm ~/.local/bin/spur`. There is nothing else on disk.

Installed this way, `spur` is a command like any other: run it from anywhere
inside a project and it finds the Spurfile by walking up from the current
directory.

### Locally, vendored into the project

Copy the runner to the root of the repository, next to the Spurfile, and
commit it:

```sh
curl -fsSL https://raw.githubusercontent.com/esliph/spur/<tag>/spur -o spur
chmod +x spur
git add spur Spurfile && git commit -m "chore: vendor spur"
```

The runner is one file with no dependencies beyond `sh` and `awk`, so
committing it is not the same kind of decision as committing a binary: it is
about 330 lines of readable shell, it diffs, and it is the same file on every
platform. From then on the tasks run with no install step at all:

```console
$ ./spur --list
$ ./spur test -k login
```

This is what makes a CI job or a minimal container work with no setup line:
there is nothing to fetch, no architecture to pick and no version to pin at
run time — the version is the one in the commit you checked out.

Two details worth knowing:

- **Chained calls stay inside the project.** A `spur build` in a task body
calls the same file that started the run (the runner injects a `spur`
function pointing at its own absolute path), so a vendored copy never hands
off to a different version that happens to be on the `PATH`.
- **`./spur` only works from the root.** It is a path, not a command, so from
a subdirectory it is `../spur test`, or `"$SPUR_ROOT/spur"` from inside a
task body. If you want the convenience of running `spur` from anywhere in
the tree, install it globally as well — the two do not conflict.

Pinning the vendored copy to a tag is what makes upgrades explicit: replace
the file, run the suite, and the change shows up as a diff in review.

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

## Build first, then run pytest. Arguments go straight to pytest:
##   spur test -k login -vv
test: ## run the tests
  spur build
  pytest -q "$@"

##@ Database
db-reset: ## recreate the database (destructive)
  dropdb --if-exists app && createdb app
```

```console
$ spur --list
Spurfile: /home/usr/project/Spurfile

Tasks
  build      build the image
  test       run the tests

Database
  db-reset   recreate the database (destructive)

$ spur --describe test
test: run the tests

Build first, then run pytest. Arguments go straight to pytest:
  spur test -k login -vv

$ spur test -k login -vv
```

## The language

- A line matching `^[A-Za-z0-9_.-]+:` opens a task. Names may contain `-` and
`.` (`db-reset`, `docker.build`).
- `## text` in the header is the description shown by `--list`. A task
without one is still runnable.
- `##` lines at column zero right above a header are the task's long help,
shown by `spur --describe <task>`. The block must touch the header: a blank
line, a `#` comment or a `##@` in between detaches it. Each line loses `##`
and one space; the rest, indentation included, is printed as written, and a
bare `##` is a blank line. To the shell they are ordinary comments.
- `##@ Title` at column zero opens a section: `--list` groups the tasks that
follow under that heading, in file order. Tasks before the first `##@`, or
after a `##@` with no title, are listed under `Tasks`. A section with no
tasks is not shown. To the shell it is an ordinary comment.
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


| Flag              | Effect                                                        |
| ----------------- | ------------------------------------------------------------- |
| `-f FILE`         | use FILE instead of searching for a Spurfile                  |
| `-C DIR`          | change to DIR before anything else                            |
| `-l`, `--list`    | list the tasks and exit                                       |
| `-n`              | print the assembled script instead of running it              |
| `--check`         | syntax-check the task, or every task, without running it      |
| `--names`         | print the task names, one per line, and exit                  |
| `--describe`      | print the task's long help (its `##` block) and exit          |
| `-x`              | trace commands (`set -x`) after the preamble, with `PS4='$ '` |
| `-h`, `--help`    | show help                                                     |
| `-v`, `--version` | show the version                                              |


`spur` with no task name lists the tasks. Short flags cannot be grouped
(`-xn` is not `-x -n`).

`spur --check` validates the Spurfile in CI without running anything: it
assembles each task as `-n` would and hands it to `sh -n`, which parses but
does not execute. An `if` without `fi` or an unterminated heredoc fails with
65, every broken task is reported, and success prints nothing. It checks
syntax only: a misspelled command or an unset variable still passes. Name a
task (`spur --check deploy`) to check just that one. The line numbers in the
errors refer to the assembled script, so `spur -n <task>` shows what they
point at.

`--list` is for people; `spur --names` is for programs. It prints the task
names in file order, one per line, with no header, sections or descriptions,
and prints nothing at all when there are no tasks. Errors go to stderr only,
with the usual exit codes. It cannot be combined with `-l`, `-n`, `-x` or
`--check`.

```sh
for t in $(spur --names); do spur --check "$t"; done
```

`spur --describe <task>` documents a task's interface without the runner
interpreting its arguments. It prints `task: description` from the header,
then the `##` block above it; with neither, `task: (no description)`. It
runs nothing, needs a task name (64 without one), exits 67 for an unknown
task, and cannot be combined with `-l`, `-n`, `-x`, `--check` or `--names`.
It is `--describe` and not `-h`, because `spur test -h` belongs to the task.

### Shell completion

Each snippet completes task names for the first word after `spur` and falls
back to file names after it. They call the `spur` on your `PATH`.

```bash
# bash (~/.bashrc)
_spur() { [ "$COMP_CWORD" -eq 1 ] && COMPREPLY=($(compgen -W "$(spur --names 2>/dev/null)" -- "$2")); }
complete -o default -F _spur spur
```

```zsh
# zsh (~/.zshrc, after compinit)
_spur() { if (( CURRENT == 2 )); then compadd -- ${(f)"$(spur --names 2>/dev/null)"}; else _files; fi }
compdef _spur spur
```

```fish
# fish (~/.config/fish/completions/spur.fish)
complete -c spur -f -n __fish_is_first_arg -a '(spur --names 2>/dev/null)'
```

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


| Variable              | Contents                                                  |
| --------------------- | --------------------------------------------------------- |
| `SPUR_BIN`            | absolute path of the runner                               |
| `SPUR_ROOT`           | the Spurfile's directory (= the task's working directory) |
| `SPUR_INVOCATION_DIR` | the directory you called from                             |
| `SPUR_TASK`           | the running task's name                                   |
| `SPUR_STACK`          | the call chain, used by the recursion guard               |


### Exit codes

A task's own exit code is propagated unchanged. Runner errors use the
`sysexits` range so they never collide with one.


| Code           | Meaning              |
| -------------- | -------------------- |
| *(the task's)* | propagated unchanged |
| 64             | usage error          |
| 65             | malformed Spurfile   |
| 66             | Spurfile not found   |
| 67             | unknown task         |
| 68             | recursion detected   |


## Coming from make


| make                      | spur                                                                          |
| ------------------------- | ----------------------------------------------------------------------------- |
| `make <target>`           | `spur <task>`                                                                 |
| mandatory TAB             | any indentation; spaces are canonical                                         |
| one shell per recipe line | one shell for the whole body: `cd` and variables persist                      |
| `$$` to escape `$`        | nothing is expanded; `$` arrives intact                                       |
| `.PHONY`                  | every task is phony by construction                                           |
| `@` per line              | `spur -x` is off by default; silence a stretch with `{ set +x; } 2>/dev/null` |
| `-` per line              | `|| true`                                                                     |
| `target: deps`            | call `spur deps` from the body                                                |
| `include`, `ifeq`         | the preamble has real `.` and `if`                                            |
| `$(MAKE) -C sub`          | `spur -C sub build`                                                           |


## License

MIT. See [LICENSE](LICENSE).