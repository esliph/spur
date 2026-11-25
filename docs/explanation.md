# Why spur works the way it does

This page explains the design: the problem spur solves, where it sits next
to make, just and Task, how a task runs, and the costs that follow from those
choices. For the exact rules, see [reference.md](reference.md).

## The problem

`make` is a build system that most projects use as a task runner. Once every
target is `.PHONY`, its engine (the timestamp graph, the pattern rules, the
built-in recipes for C) does no work. Its gotchas still apply: the mandatory
TAB, a separate shell for each recipe line so `cd` does not persist, `$$` to
get a literal `$` to the shell, and a different dialect on BSD and on GNU.

`just` and Task fix those gotchas, and they cost something make never did: a
compiled binary. On a laptop that is one `brew install`. In a CI image, an
Alpine container, a locked-down server or a machine with no toolchain, it is
a download per architecture, a checksum, a version to pin, and one more thing
that can be missing when you need it.

spur keeps make's shape: a file of named recipes at the root of the
repository, run as `spur test`. It drops the build engine, and it ships as one
`sh` script, so there is nothing to install.

## Next to the alternatives

|                        | make                    | just                  | Task                        | spur                          |
| ---------------------- | ----------------------- | --------------------- | --------------------------- | ----------------------------- |
| Runtime to install     | usually already present | a binary per platform | a binary per platform       | none: `sh`, `awk`, `cat`      |
| In a minimal container | not always there        | fetch the right arch  | fetch the right arch        | runs on what is already there |
| What it is             | a build system          | a task runner         | a task runner               | a task runner                 |
| Dependency graph       | yes, by timestamp       | yes, ordering         | yes, plus up-to-date checks | none, by design               |
| Argument passthrough   | none; use a variable    | declared parameters   | variables on the CLI        | `"$@"`, verbatim              |
| Native Windows         | no                      | yes                   | yes                         | no                            |

Where a binary is not a problem, `just` and Task are the better tools: they
have declared parameters, richer features, and they run natively on Windows. spur
wins in one place, and a lot of work happens there: a container or a server
where you would rather add nothing.

## The design choices

### Nothing to install

The runner is one file. It depends on `sh`, `awk` and `cat`, and a test runs
it with only those three on `PATH`. You can fetch it with `curl`, or commit
it to the repository so that anyone who clones it can run `./spur test` with
no package manager and no network.

The same rule shapes the code. The runner splits paths with parameter
expansion instead of calling `dirname` or `basename`, and parses the
Spurfile once per run. Every process it starts is paid on every run, and
again by every `spur` that a task calls.

### Positional passthrough

`spur test -k login -vv` gives `-k login -vv` to the body as `"$@"`. With
make, the usual workarounds are a variable (`make test ARGS='-k login'`) or a
wrapper script. It is the feature most often missing when a Makefile serves
as a task runner.

The rule that makes it work is simple: the first word that does not start
with `-` is the task, and everything after it belongs to the task. That is
why `spur -n test` is a dry run and `spur test -n` passes `-n` to the task,
and why short flags cannot be grouped. It is also why a task's long help is
`spur --describe test` and not `spur test -h`: the `-h` belongs to the task.

### One shell for the whole task

The body is an ordinary shell block, not a dialect. `cd` and variables
persist, and `if`, `for` and heredocs work as they do in a script. `set -e`
stops the task at the first failure.

### The runner expands nothing

`$IMAGE`, `$(date)`, `${x:-y}` and `$$` reach the shell byte for byte. There is
no template layer to escape, so there is nothing to learn beyond the shell.

### A small, readable program

The runner is a few hundred lines of `sh`, the parser included. When it does
something surprising, you can read the source, and it is the same file that
you installed.

## How a task runs

A run has four stages:

1. **Locate.** spur finds the Spurfile: the nearest `Spurfile` or
   `spurfile` going up from the current directory, or the file named with
   `-f`. On macOS and Windows the filesystem ignores case, so either name
   finds the file. On Linux they are different names, and spur accepts both
   so that a project works the same everywhere. spur then changes to the Spurfile's directory,
   so every task runs from there.
2. **Parse.** One awk program reads the Spurfile once and returns the
   preamble and the task body.
3. **Assemble.** spur joins `set -e`, a `spur` function that points at the
   runner itself, the preamble, the optional trace settings, and the dedented
   body into one script. `spur -n <task>` prints that script.
4. **Run.** spur replaces itself with `sh -c "$script" "spur <task>" "$@"`.

That single `sh -c` explains three things:

- **stdin stays free.** No pipe feeds the script, so a task can prompt the
  user.
- **There is no temporary file.** The script is an argument, not a file on
  disk.
- **Errors name the task.** `$0` is `spur <task>`, so the shell prints
  `spur build: line 3: ...`.

The injected `spur` function means a chained call runs the same file that
started the run. A vendored copy never hands off to a different version that
happens to be on `PATH`.

## What it costs

These follow from the design. They are accepted on purpose, not planned
work.

1. **A task can run more than once.** With no graph, there is no
   deduplication. If `build` calls `deps` and `lint` calls `deps`, `deps`
   runs twice. In return, every call is explicit and visible in the body, and
   argument passthrough works the same way for every call.
2. **No parallelism and no incremental rebuild.** Both need a dependency
   graph. `-j`, timestamps and pattern rules are outside spur's scope, not
   only this version's. To compile software, use make or CMake, and call them
   from a spur task.
3. **`-n` does not follow the call chain.** The dry run shows the script of
   the task you named. A `spur deps` inside the body happens at run time, and
   finding it ahead of time would mean interpreting shell.
4. **make's per-line `@` is not possible.** make runs one line at a time.
   spur gives the whole block to one `sh` and does not know where each command
   starts. Use `spur -x` to trace a run, or `{ set +x; } 2>/dev/null` and
   `set -x` around a part of the body. The redirection is needed because a
   bare `set +x` prints itself before tracing stops.
5. **The preamble runs for every task.** That does not matter when it is
   cheap (assignments, `.env`, functions). It costs time if you put real work
   there.
6. **No native Windows.** spur needs a POSIX shell: Git Bash, MSYS2, WSL or
   Cygwin. make needs the same. "Portable" here means *runs on any Unix,
   under any POSIX shell, with no runtime installed*, not *runs natively
   everywhere*.
7. **Chained calls do not inherit `-f`.** Inside a body, `spur other` finds
   the Spurfile by the usual search from `SPUR_ROOT`. Passing `-f` on would
   break `spur -C sub build` inside a body.

## The recursion guard

With no graph, nothing stops a task from calling itself, directly or through
other tasks. spur keeps the chain in `SPUR_STACK`: one line per running task,
with its name and the physical path of its Spurfile. If a task is already in
the chain for the same Spurfile, spur exits 68 and prints the chain.

The guard keys on the Spurfile as well as the name, so `install` can call
`spur -C sub install`: that is another task. It uses the physical path, so a
symlinked directory does not hide a real loop. Repeated calls in sequence are
allowed, because a task can legitimately run more than once.

## Exit codes in the sysexits range

A task's exit code is passed through unchanged, so a CI job sees what the
test tool returned. spur's own errors use 64 to 68, the range that
`sysexits.h` reserves for usage and input errors, which ordinary tools
seldom return. A script can then tell "the Spurfile is broken" (65) from
"the tests failed" (1). The separation is a convention, not a guarantee: a
task that itself exits 65 looks the same to the caller.
