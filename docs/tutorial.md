# Write your first Spurfile

In this tutorial you write a Spurfile with two tasks, run them, pass them
arguments, and look at what spur runs before it runs it. It takes about ten
minutes. You need a POSIX shell (on Windows: Git Bash, MSYS2, WSL or
Cygwin) and nothing else.

## 1. Install spur

Download the runner into `~/.local/bin` and make it executable:

```sh
curl -fsSL https://raw.githubusercontent.com/esliph/spur/master/spur \
  -o ~/.local/bin/spur && chmod +x ~/.local/bin/spur
```

Check that your shell finds it:

```sh
spur -v
```

spur prints `spur` and its version. If your shell says `spur: not found`,
add `~/.local/bin` to your `PATH`
([how](how-to.md#install-spur-for-your-user)).

## 2. Run a task

Make a directory for the tutorial and go into it:

```sh
mkdir hello && cd hello
```

Create a file named `Spurfile` with this content:

```sh
hello:
  echo "Hello from spur"
```

`hello:` opens a task named `hello`. The indented line below it is its body.

Run the task:

```console
$ spur hello
Hello from spur
```

## 3. List the tasks

Add a description after `##` on the header line:

```sh
hello: ## say hello
  echo "Hello from spur"
```

Run `spur` with no task:

```console
$ spur
Spurfile: /home/me/hello/Spurfile

Tasks
  hello   say hello
```

spur lists the tasks and their descriptions. The first line shows which
Spurfile it found.

## 4. Pass an argument

Change the body so that it uses the first argument, with `world` as the
default:

```sh
hello: ## say hello
  echo "Hello, ${1:-world}"
```

Run it with and without an argument:

```console
$ spur hello
Hello, world
$ spur hello Ana
Hello, Ana
```

Every word after the task name goes to the body, as `"$1"`, `"$2"` and
`"$@"`. spur does not read or change them.

## 5. Add a preamble

Lines before the first task form the preamble. It runs at the start of every
task. Move the greeting into a variable there:

```sh
GREETING=Hello

hello: ## say hello
  echo "$GREETING, ${1:-world}"
```

```console
$ spur hello Ana
Hello, Ana
```

## 6. Call a task from another task

Add a second task that greets each name it receives. It calls `hello` once
per name:

```sh
GREETING=Hello

hello: ## say hello
  echo "$GREETING, ${1:-world}"

greet-all: ## say hello to each name
  for name in "$@"; do
    spur hello "$name"
  done
```

The body of `greet-all` has several lines. One shell runs all of them, so the
`for` loop works as it would in a script.

Run it:

```console
$ spur greet-all Ana Bruno Carla
Hello, Ana
Hello, Bruno
Hello, Carla
```

## 7. Look before you run

Print the script that spur would run, without running it:

```console
$ spur -n greet-all
set -e
spur() { "$SPUR_BIN" "$@"; }
GREETING=Hello
for name in "$@"; do
  spur hello "$name"
done
```

This is the whole script: `set -e`, a `spur` function that calls the same
runner, your preamble, and the body with its indentation removed.

Check every task for syntax errors, again without running anything:

```console
$ spur --check
```

No output means no errors.

Now mistype a task name:

```console
$ spur helo
spur: unknown task: helo
spur: did you mean: hello?
spur: run 'spur --list' to see the available tasks
```

## What you built

You have a Spurfile with a preamble and two tasks. One task takes arguments,
and the other calls it in a loop. You listed the tasks, printed a task's
script, and checked the file.

Next:

- [how-to.md](how-to.md): recipes for real projects, such as vendoring spur,
  CI, debugging and moving from make.
- [reference.md](reference.md): every rule of the Spurfile and every flag.
- [explanation.md](explanation.md): why spur works this way, and what it
  does not do.
