# How-to guides

Short recipes for common jobs. Each one assumes you already have a Spurfile
and know how to run a task. If you do not, start with
[tutorial.md](tutorial.md). For every flag and rule, see
[reference.md](reference.md).

- [Install spur for your user](#install-spur-for-your-user)
- [Vendor spur into a repository](#vendor-spur-into-a-repository)
- [Pass arguments to a tool](#pass-arguments-to-a-tool)
- [Share setup between tasks](#share-setup-between-tasks)
- [Call one task from another](#call-one-task-from-another)
- [Run tasks of another directory](#run-tasks-of-another-directory)
- [Document your tasks](#document-your-tasks)
- [Check the Spurfile in CI](#check-the-spurfile-in-ci)
- [Debug a task](#debug-a-task)
- [Set up shell completion](#set-up-shell-completion)
- [Move a Makefile to spur](#move-a-makefile-to-spur)
- [Use spur on Windows](#use-spur-on-windows)

## Install spur for your user

Use this to have `spur` on your own machine for every project.

1. Download the runner into a directory on your `PATH` and make it
   executable. `master` is the latest development version:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/esliph/spur/master/spur \
     -o ~/.local/bin/spur && chmod +x ~/.local/bin/spur
   ```

   For a specific version, replace `master` with a tag from the
   [tag list](https://github.com/esliph/spur/tags).
   [CHANGELOG.md](../CHANGELOG.md) says what each version changed.

2. If `~/.local/bin` is not on your `PATH`, add this line to your shell's rc
   file:

   ```sh
   export PATH="$HOME/.local/bin:$PATH"
   ```

3. Check the install with `spur -v`.

To upgrade, run step 1 again with another ref. To uninstall, delete the
file: `rm ~/.local/bin/spur`. spur writes nothing else to disk.

## Vendor spur into a repository

Use this so that anyone who clones the repository, a CI runner or a
container included, can run the tasks with nothing to install.

1. Download the runner to the root of the repository, next to the Spurfile,
   pinned to a tag:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/esliph/spur/<tag>/spur -o spur
   chmod +x spur
   ```

   Replace `<tag>` with a tag from the
   [tag list](https://github.com/esliph/spur/tags).

2. Commit it:

   ```sh
   git add spur Spurfile && git commit -m "chore: vendor spur"
   ```

3. Run tasks through the vendored copy:

   ```sh
   ./spur --list
   ./spur test
   ```

Notes:

- `./spur` is a path, so it works only from the root. From a subdirectory
  use `../spur test`. Inside a task body, write plain `spur`: it is a
  function that calls the same file. To type `spur` from anywhere, also
  install it for your user. The two do not conflict.
- A chained `spur build` inside a task always runs the vendored file, not
  another `spur` on `PATH`.
- To upgrade, download another tag over the file, run your checks, and
  commit. The upgrade shows up as a diff in review.

## Pass arguments to a tool

Put `"$@"` where the tool takes its arguments:

```sh
test: ## run the tests
  pytest -q "$@"
```

```sh
spur test -k login -vv    # runs: pytest -q -k login -vv
```

Runner flags go before the task name. Everything after the task name goes to
the task, even words that look like spur flags: `spur test -n` passes `-n`
to `pytest`.

For a required argument, let the shell check it:

```sh
deploy: ## deploy to an environment
  env=${1:?usage: spur deploy ENV}
  ./scripts/deploy.sh "$env"
```

## Share setup between tasks

Put shared variables, functions and includes before the first task. That is
the preamble, and it runs at the start of every task.

```sh
IMAGE=myapp:latest
: "${ENV:=dev}"
[ -f .env ] && . ./.env

log() { printf '>> %s\n' "$1"; }

build: ## build the image
  log "building $IMAGE for $ENV"
  docker build -t "$IMAGE" .
```

Keep the preamble cheap. It runs for every task, so slow commands there slow
down every run. To turn on `set -u` for all tasks, add it to the preamble.

## Call one task from another

Call `spur` from the body:

```sh
build: ## build the image
  docker build -t myapp .

release: ## build, then push
  spur build
  docker push myapp
```

- Arguments work as on the command line: `spur build --no-cache`.
- The called task runs in its own shell. Variables set in the caller's body
  do not reach it; export them, or put them in the preamble.
- A task called twice runs twice. spur has no dependency graph.
- A loop (`a` calls `b`, `b` calls `a`) stops with exit code 68.

## Run tasks of another directory

To run a task of a Spurfile in another directory, use `-C`:

```sh
spur -C services/api test
```

To use a Spurfile with another name or location, use `-f`:

```sh
spur -f ci/tasks.sf lint
```

A `spur other` inside a task does not inherit `-f`. It searches for
`Spurfile` or `spurfile` from the task's directory, so under
`-f ci/tasks.sf` it does not find `tasks.sf` and exits 66. In a file meant
for `-f`, name it in the call: `spur -f "$SPUR_ROOT/tasks.sf" other`.

The task runs in the directory that holds the Spurfile. `SPUR_INVOCATION_DIR`
holds the directory you called from, for tasks that need it:

```sh
fmt: ## format the files of the current directory
  cd "$SPUR_INVOCATION_DIR" && shfmt -w .
```

## Document your tasks

1. Add a one-line description after `##` in the header. `spur --list` shows
   it.

   ```sh
   test: ## run the tests
   ```

2. Add a long help as `##` lines directly above the header. `spur --describe
   test` prints it.

   ```sh
   ## Arguments go to pytest:
   ##   spur test -k login -vv
   test: ## run the tests
   ```

3. Group tasks into sections with `##@ Title` lines. `--list` shows the tasks
   under their section.

   ```sh
   ##@ Database
   db-reset: ## recreate the database
   ```

The long help must touch the header: a blank line, a comment or a `##@` line
between them detaches it.

## Check the Spurfile in CI

Add a step that runs:

```sh
spur --check
```

It parses every task with `sh -n` and runs nothing. It prints nothing on
success and exits 65 for a syntax error, such as an `if` without `fi` or a
heredoc that is never closed. It checks syntax only: a misspelled command or
an unset variable still passes.

To check one task, name it: `spur --check deploy`.

## Debug a task

- **See what runs.** `spur -n <task>` prints the assembled script: the
  prelude, the preamble and the dedented body. Line numbers in error
  messages count lines of this script.
- **Trace a run.** `spur -x <task>` prints each command, prefixed with `$ `,
  before it runs. The preamble is not traced.
- **Trace part of a body.** Turn tracing on and off inside the body:

  ```sh
  deploy:
    set -x
    ./scripts/upload.sh
    { set +x; } 2>/dev/null
    echo "done"
  ```

- **Keep going after a failure.** `set -e` is on. Add `|| true` to a command
  whose failure you want to ignore.

## Set up shell completion

Each snippet completes task names for the first word after `spur` and file
names after that. They call the `spur` on your `PATH`.

bash, in `~/.bashrc`:

```bash
_spur() { [ "$COMP_CWORD" -eq 1 ] && COMPREPLY=($(compgen -W "$(spur --names 2>/dev/null)" -- "$2")); }
complete -o default -F _spur spur
```

zsh, in `~/.zshrc`, after `compinit`:

```zsh
_spur() { if (( CURRENT == 2 )); then compadd -- ${(f)"$(spur --names 2>/dev/null)"}; else _files; fi }
compdef _spur spur
```

fish, in `~/.config/fish/completions/spur.fish`:

```fish
complete -c spur -f -n __fish_is_first_arg -a '(spur --names 2>/dev/null)'
```

`spur --names` is the interface for scripts like these: names only, one per
line, nothing else.

## Move a Makefile to spur

1. Copy each `.PHONY` target into a Spurfile task with the same name.
2. Translate the recipes with the table below.
3. Move variables and `include`s into the preamble.
4. Run `spur --check`, then each task.

| make | spur |
| --- | --- |
| `make <target>` | `spur <task>` |
| mandatory TAB | any indentation; spaces are the convention |
| one shell per recipe line | one shell for the whole body: `cd` and variables persist |
| `$$` to escape `$` | write `$`; spur expands nothing |
| `.PHONY` | every task is phony |
| `@` per line | spur prints no commands unless you pass `-x` |
| `-` per line | `|| true` |
| `target: deps` | call `spur deps` from the body |
| `include`, `ifeq` | the preamble has real `.` and `if` |
| `$(MAKE) -C sub` | `spur -C sub build` |
| `make test ARGS='-k x'` | `spur test -k x`, with `"$@"` in the body |

Keep make for targets that build files from other files. A spur task can
call it: `make -C native`.

## Use spur on Windows

spur needs a POSIX shell. Run it from Git Bash, MSYS2, WSL or Cygwin.

A vendored runner must keep LF line endings: CRLF breaks its shebang. With
Git, add this line to `.gitattributes`:

```
spur text eol=lf
```

A Spurfile saved with CRLF works: spur drops the carriage returns.
