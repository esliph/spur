# spur

**Simple Portable Universal Runner**: a task runner in one POSIX `sh` script.

spur reads a `Spurfile` of named tasks and runs the one you ask for, in a
single shell, with your arguments passed through as `"$@"`. It needs only
`sh`, `awk` and `cat`, so it runs on any Unix, in a minimal container and
in CI with nothing to install.

spur runs tasks; it does not build software. It has no dependency graph, no
timestamp rebuilds and no pattern rules, by design.

## Example

```sh
# Spurfile
IMAGE=myapp:latest

build: ## build the image
  docker build -t "$IMAGE" .

## Arguments go to pytest:
##   spur test -k login -vv
test: ## run the tests
  spur build
  pytest -q "$@"
```

```console
$ spur
Spurfile: /home/me/project/Spurfile

Tasks
  build   build the image
  test    run the tests

$ spur test -k login -vv
```

What this shows:

- **Arguments pass through.** `-k login -vv` reaches `pytest` as `"$@"`.
- **One shell per task.** `cd` and variables persist across the body's
  lines, and `set -e` stops at the first failure.
- **No escaping.** spur expands nothing: `$IMAGE`, `$(date)` and `$$` reach
  the shell as written.
- **Tasks call tasks.** `spur build` inside a body runs the same runner.

## Install

Download the runner into a directory on your `PATH`:

```sh
curl -fsSL https://raw.githubusercontent.com/esliph/spur/master/spur \
  -o ~/.local/bin/spur && chmod +x ~/.local/bin/spur
```

Check it:

```console
$ spur -v
spur 0.3.1
```

To pin a version, replace `master` with a
[tag](https://github.com/esliph/spur/tags). To let
anyone who clones your repository run the tasks with no install, commit the
runner next to the Spurfile and call it as `./spur`: see
[Vendor spur into a repository](docs/how-to.md#vendor-spur-into-a-repository).

On Windows, run spur from Git Bash, MSYS2, WSL or Cygwin.

## Documentation

| Page | Read it to |
| --- | --- |
| [Tutorial](docs/tutorial.md) | write and run your first Spurfile, step by step |
| [How-to guides](docs/how-to.md) | vendor spur, pass arguments, check in CI, debug a task, set up completion, move from make |
| [Reference](docs/reference.md) | look up the Spurfile syntax, the flags, the environment variables and the exit codes |
| [Explanation](docs/explanation.md) | understand why spur exists, how a task runs, and what the design costs |

`spur --help` prints the flags and exit codes.

## Is spur for you?

Use spur when you want make's shape (a file of named commands at the root of
the repository) without make's gotchas, and you cannot or do not want to
install a binary.

Use something else when:

- **You build files from other files.** Use make or CMake. A spur task can
  call them.
- **A binary is fine and you want more features.** `just` and Task have
  declared parameters and run natively on Windows.

[Explanation](docs/explanation.md#what-it-costs) lists every trade-off.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the test suite, the shell matrix
and the release process. [CHANGELOG.md](CHANGELOG.md) lists what each
version changed.

## License

MIT. See [LICENSE](LICENSE).
