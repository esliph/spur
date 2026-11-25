# Reference

The complete contract of spur: the Spurfile language, the command line, how
a run finds its Spurfile, what the task shell receives, and the exit codes.
Each section stands on its own. For the reasons behind these rules, see
[explanation.md](explanation.md).

- [The Spurfile](#the-spurfile)
- [Command line](#command-line)
- [Finding the Spurfile](#finding-the-spurfile)
- [The task shell](#the-task-shell)
- [Environment variables](#environment-variables)
- [Exit codes](#exit-codes)
- [Diagnostics](#diagnostics)

## The Spurfile

A Spurfile is a preamble followed by tasks.

```sh
# Everything before the first task is the preamble.
IMAGE=myapp:latest
[ -f .env ] && . ./.env

## Long help: shown by `spur --describe build`.
build: ## build the image
  docker build -t "$IMAGE" .

##@ Database
db-reset: ## recreate the database
  dropdb --if-exists app && createdb app
```

### Task header

- A line that matches `^[A-Za-z0-9_.-]+:` opens a task. A name may contain
  letters, digits, `_`, `-` and `.` (`db-reset`, `docker.build`).
- A header takes no prerequisites. `build: deps` is an error (65). To run
  another task, call `spur deps` from the body.
- `## text` after the colon is the task's description. `--list` shows it.
  A task without one still runs.

### Body

- The body is the indented lines after the header. Spaces are the
  convention; a tab also works.
- Before the body runs, spur removes the longest leading whitespace that
  all its non-blank lines share. Nested `if`, `for` and heredocs keep their
  relative shape.
- A blank line belongs to the body. Only a line with content at column zero
  ends it. That line must be a task header or a comment; any other line is
  an error (65: `expected a task header`).
- A heredoc terminator goes at the body's indentation. The dedent moves it to
  column zero, where the shell looks for it. A terminator written at column
  zero in the Spurfile ends the task instead, and the heredoc is left open.

### Preamble

- Everything before the first task header is the preamble.
- The preamble runs at the start of every task, before the body. Put
  variables, functions and `.` includes there.

### Comments, long help and sections

| Line at column zero | Meaning |
| --- | --- |
| `# text` | A comment. Allowed anywhere. |
| `## text` directly above a header | The task's long help, shown by `--describe`. |
| `##@ Title` | Opens a section in `--list`. |
| `###` or more `#` | A comment. Never part of a long help. |

Long help rules:

- The `##` block must touch the header. A blank line, a `#` or `###`
  comment, or a `##@` line between them detaches it.
- Each line loses `##` and one space. The rest, indentation included, is
  printed as written. A bare `##` prints a blank line.

Section rules:

- `--list` groups the tasks after a `##@ Title` under that title, in file
  order.
- Tasks before the first `##@`, or after a `##@` with no title, go under
  `Tasks`.
- A section with no tasks is not shown.

To the shell, every one of these lines is an ordinary comment.

### Expansion

spur expands nothing. `$IMAGE`, `$(date)`, `${x:-y}` and `$$` reach the
task shell byte for byte.

### Line endings

A Spurfile with CRLF line endings works. spur removes the carriage returns
before it parses the file.

## Command line

```
spur [runner flags] <task> [task arguments...]
```

The first word that does not start with `-` is the task name. Every word
after it goes to the task as `"$@"`, unchanged.

```sh
spur -n test           # -n is the runner's: dry run of 'test'
spur test -n           # -n is the task's: it arrives as "$1"
spur -C api test -k x  # -C api is the runner's; -k x is the task's
```

### Flags

| Flag | Effect |
| --- | --- |
| `-f FILE` | Use FILE. Do not search for a Spurfile. |
| `-C DIR` | Change to DIR before anything else, `-f` included. |
| `-l`, `--list` | List the tasks and exit. |
| `-n` | Print the assembled script of the task. Do not run it. |
| `-x` | Trace the task's commands (`set -x` with `PS4='$ '`), after the preamble. |
| `--check` | Syntax-check the task, or every task, with `sh -n`. Run nothing. |
| `--names` | Print the task names, one per line, and exit. |
| `--describe` | Print the task's description and long help, and exit. |
| `-h`, `--help` | Show the help and exit. |
| `-v`, `--version` | Print `spur X.Y.Z` and exit. |

Rules:

- `spur` with no task lists the tasks, like `-l`.
- Short flags cannot be grouped. `-xn` is an unknown option (64).
- `-n` and `-x` need a task (64 without one).
- `--check`, `--names` and `--describe` cannot be combined with `-l`, `-n`,
  `-x` or with each other (64).

### `--list`

For people. Prints the Spurfile path, then the tasks by section, with their
descriptions.

```console
$ spur --list
Spurfile: /home/me/project/Spurfile

Tasks
  build      build the image

Database
  db-reset   recreate the database
```

### `--names`

For programs. Prints the task names in file order, one per line, with no
header, sections or descriptions. Prints nothing when there are no tasks.
Errors go to stderr only.

### `--describe <task>`

Prints `task: description` from the header, then the long help. A task with
neither prints `task: (no description)`. Needs a task (64) and exits 67 for
an unknown one.

### `--check [task]`

Assembles each task as `-n` would and passes it to `sh -n`, which parses
without running.

- With no task, checks the preamble and every task, and reports every broken
  one.
- With a task, checks only that one.
- Silent on success. Exits 65 on a syntax error, such as an `if` without `fi`
  or a heredoc that is never closed.
- Checks syntax only. A misspelled command or an unset variable passes.
- Line numbers in the errors count lines of the assembled script.
  `spur -n <task>` shows that script.

## Finding the Spurfile

1. With `-C DIR`, spur changes to DIR first.
2. With `-f FILE`, spur uses FILE and does not search.
3. Otherwise spur looks for `Spurfile`, then `spurfile`, in the current
   directory, then in each parent up to `/`. The nearest one wins. In a
   directory that has both (possible only on a case-sensitive filesystem),
   `Spurfile` wins.
4. spur changes to the directory that holds the Spurfile. Every task runs
   there.

## The task shell

spur builds one script and runs it with:

```sh
sh -c "$script" "spur <task>" "$@"
```

The script holds, in order:

1. `set -e`.
2. A `spur` function that calls the same runner file, by its absolute path.
3. The preamble, as written.
4. With `-x`: `PS4='$ '` and `set -x`.
5. The dedented body.

Consequences:

- One shell runs the whole body. `cd` and variables persist from line to
  line.
- `set -e` is on: the first failing command ends the task with its status.
  `set -u` is off; add it to the preamble if you want it.
- stdin is the caller's, so interactive tasks work.
- `spur <task>` inside a body runs the same runner file, even when another
  `spur` is on `PATH`.
- A chained `spur <task>` does not inherit `-f`. It finds the Spurfile by the
  usual search, from `SPUR_ROOT`.
- A task that is already running, for the same Spurfile, cannot be called
  again from inside its own chain (68). The same task called twice in
  sequence is allowed, and so is a task of the same name in another
  Spurfile.

## Environment variables

spur exports these to the task:

| Variable | Contents |
| --- | --- |
| `SPUR_BIN` | Absolute path of the runner. |
| `SPUR_ROOT` | The Spurfile's directory, which is the task's working directory. |
| `SPUR_INVOCATION_DIR` | The directory spur was called from. |
| `SPUR_TASK` | The running task's name. |
| `SPUR_STACK` | The call chain, one frame per line: the task name, a space, and the physical path of its Spurfile. |

Every other variable reaches the task as the caller set it. Names that start
with `SPUR_` or `spur_` belong to spur.

## Exit codes

A task's own exit code is propagated unchanged. Runner errors use 64 to 68,
the range that `sysexits.h` reserves for usage and input errors, which
ordinary tools seldom return. A task that itself exits 65 still looks like a
malformed Spurfile to the caller.

| Code | Meaning |
| --- | --- |
| *(the task's)* | Propagated unchanged. |
| 64 | Usage error: unknown option, missing argument, conflicting flags, no task given. |
| 65 | Malformed Spurfile, or `--check` found a syntax error. |
| 66 | Spurfile not found, or `-f FILE` does not exist. |
| 67 | Unknown task. |
| 68 | Recursion detected. |

## Diagnostics

- Runner errors go to stderr, prefixed `spur:`.
- A parse error names the file and line: `spur: Spurfile:1: task header takes
  no prerequisites: build`.
- An unknown task suggests up to three close names.
- Errors from the task shell are labelled with the task:
  `spur build: line 3: ...`. The line counts lines of the assembled script;
  `spur -n build` shows it.
