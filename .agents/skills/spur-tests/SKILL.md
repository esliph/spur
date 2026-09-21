---
name: spur-tests
description: Expert on spur's behavior test suite - running it (`sh tests/run.sh`, selecting a case or a group, the dash/bash/busybox matrix), writing a new case in `tests/cases/`, debugging a failing one, keeping the suite honest when the runner changes, and spotting where coverage is thin. Use this whenever work in this repository touches `tests/`, adds or edits a case, or changes anything in the `spur` runner - every behavior change here ships with a test, so this applies even to a "trivial" parser or flag tweak. Also use it when asked to run the tests, explain a FAIL, check what is covered, or improve the suite, including casual phrasings like "roda os testes", "adiciona um teste pra isso", "isso ja tem cobertura?" or "o teste X quebrou".
---

# spur's test suite

`spur` is one file of POSIX sh with an awk parser inside it. The suite is the
only thing standing between a tidy-looking refactor and a silent change in how
somebody's `Spurfile` behaves. Treat a case as a pinned promise, not as
scaffolding.

## Boundary

**Territory** — decides whether a change to the runner is adequately pinned,
and by which assertion; names and groups each case; arbitrates whether a
proposed case is worth adding or vacuous; approves what "done" means for a
behavior change, including which shells were actually run.

**Outside the boundary** — the runner's design and its user-facing contract
(the language, the CLI, the exit codes, the known limitations): pinned here,
decided and documented elsewhere in this repository. Also outside: whether a
behavior should exist at all, and how this repository is committed and
released.

**What I don't need to know** — the Spurfile of whatever project uses spur,
how spur is installed or packaged, and why the runner was designed the way it
was. A case pins observable behavior; it does not ratify the reasoning behind
it, so none of that changes which assertion is right.

**Edge contract** — receives a change to the runner, a failure log, or a
question about coverage; returns cases under `tests/cases/`, a verdict on a
proposal, or an honest stop naming what it could not verify.

**Hard dependency** — the harness contract in `tests/run.sh` and
`tests/lib.sh` (the helpers, `$runner` and `$shell_under_test`, and
exact-name-then-substring selection), and the coverage snapshot in
`references/coverage-map.md`.

## The pieces

| Path | What it is |
|---|---|
| `tests/run.sh` | The harness: picks cases, runs each in its own temp dir, prints `ok` / `FAIL`. |
| `tests/lib.sh` | Assertion helpers, sourced into every case. |
| `tests/cases/<group>-<what>.sh` | One case each. Plain sh, no framework. |
| `Spurfile` | The repo runs itself; the tasks that drive the suite are listed there. |
| `.github/workflows/ci.yml` | What CI actually runs — the authority on the matrix. |

There is no test framework and there should not be one: a tool that sells
itself as zero-dependency cannot need `bats` or `shellspec` to test itself.
That constraint is why the harness is hand-rolled, and why new cases are
written in the same sh the runner is written in.

**Two different dependency budgets.** The repository states the diet the
*runner* is on, and it is a strict one. What it does not say, and what gets
over-applied, is that the *harness* is exempt: `tests/` is ordinary tooling
and freely uses `grep`, `sed`, `diff`, `basename`, `mkdir`, `rm`.
`assert_stdout_is` is built on `diff -u` on purpose. A case rewritten to obey
the runner's diet is a case made worse for no reason.

## Running

```sh
sh tests/run.sh                        # everything
sh tests/run.sh discovery-flag-f       # exactly that case
sh tests/run.sh parse-                 # no case has that name: substring filter (a group)
sh tests/run.sh nonsense               # selects nothing -> exit 64, never a green empty run
SPUR_TEST_SHELL=dash sh tests/run.sh   # the strict-POSIX check
```

The repository also drives all of this through itself, filter included. Read
the task list in the `Spurfile` rather than recalling a task name from
memory — it is one file and it is the only place that spelling is true.

Selection resolves exact-name-first: if `tests/cases/<arg>.sh` exists, only
that case runs, even when other case names contain the argument. Otherwise the
argument is a plain substring filter, which is what makes the `group-` prefixes
worth having.

Use the raw `sh tests/run.sh` form when you are debugging the runner itself.
`./spur test` goes through the very program under test, so a broken runner can
hide a broken suite.

`SPUR_TEST_SHELL` picks the shell that executes **the runner**, not the shell
executing `run.sh`. `SPUR_TEST_TMPDIR` (default `/tmp`) is where the per-case
directories go — never leave a `Spurfile` lying around in it, because
`discovery-not-found` asserts that no ancestor of the case dir has one.

### The matrix, and the local trap

"Strict POSIX" is a claim until a matrix makes it a fact. On many machines
(macOS, Git Bash on Windows) `/usr/bin/sh` is **bash in POSIX mode**, which
happily accepts bashisms. A green `sh tests/run.sh` there proves very little.
`SPUR_TEST_SHELL=dash` is the run that actually catches non-POSIX constructs;
CI adds busybox ash for the same reason. Before claiming a change is done, run
dash at minimum, and say which shells you actually ran.

`shellcheck` is not installed everywhere. If the repository's lint task
reports "command not found", say so plainly rather than treating the missing
lint as a pass — CI will still run it.

## Reading a failure

A failing case prints `FAIL <name>` followed by its captured log, indented.
Most of that log comes from `fail()`, which dumps `stdout` and `stderr` before
exiting, so the runner's real output is usually right there.

The harness deletes its work directory on exit, so there is nothing to poke at
afterwards. To get a live case dir you can inspect, run the case by hand:

```sh
export root=$PWD runner=$PWD/spur shell_under_test=sh   # from the repo root
mkdir -p /tmp/spur-debug && cd /tmp/spur-debug
sh -c '. "$root/tests/lib.sh"; . "$root/tests/cases/parse-list.sh"'
ls   # Spurfile, stdout, stderr, expected — all left behind
```

`$runner` and `$shell_under_test` are the two variables `tests/lib.sh` expects
from the harness; supply them and any case runs standalone. The `sh -c`
wrapper matters because `fail` ends the case with `exit 1`, which would close
your own shell if you sourced the case directly. Set `shell_under_test=dash`
to reproduce a failure that only happens there. From there, `run -n <task>` is
usually the fastest way to see what the assembly stage actually produced.

## Writing a case

The file name without `.sh` **is** the case name, so it must be unique and it
is what someone will type to run it. Name it `<group>-<what-it-checks>.sh`,
where `<group>` is the prefix its neighbours already use: `ls tests/cases/` is
the live list and `CONTRIBUTING.md` says what each prefix covers. Inventing a
new prefix is a real decision, not a formality — make it only when a case
honestly fits none of the existing ones, and say that you did, because the
prefix is the whole reason `sh tests/run.sh <group>-` is worth typing.

Cases run in alphabetical order, each in its own directory, each in a
subshell. Order carries no meaning and no case may depend on another.

A case is a straight-line script — no test functions, no setup/teardown:

```sh
spurfile <<'EOF'
build: ## build it
  echo building
EOF

run build
assert_status 0
assert_stdout_is <<'EOF'
building
EOF
```

### Heredoc quoting is the trap

Nearly every mistake in this suite is a heredoc quoted the wrong way.

- `spurfile <<'EOF'` — **quoted**, almost always. The whole point of spur is
  that `$VAR`, `$(cmd)` and `$$` reach the task shell untouched; an unquoted
  heredoc would let the *case* expand them and you would be testing nothing.
- `assert_stdout_is <<EOF` — **unquoted** when the expectation contains
  `$PWD`, `$base` or another value the case computed. Quoted when it is
  literal text.

Both appear in `parse-list.sh`: a quoted heredoc writes the Spurfile, an
unquoted one interpolates `$PWD` into the expected `Spurfile:` header. When an
assertion mysteriously fails on a literal `$PWD`, this is why.

### Helpers

`tests/lib.sh` is the set of helpers a case gets, and the authority on what
each one does; `CONTRIBUTING.md` lists them in short form. Read one of the two
instead of recalling the set from memory — an assertion that does not exist
fails as a missing command, which reads like a bug in the case.

Choosing between them is the part no list can tell you, and it matters more
than it looks:

- Assertions about **assembly** should use `run -n <task>` plus
  `assert_stdout_is`. That pins the generated script byte for byte, including
  the prelude, which is exactly the thing a refactor breaks quietly.
- Assertions about **diagnostics** should use `assert_stderr_has` with the
  message text, not a regex — the message wording is part of the contract and
  a fixed string fails loudly when someone rewords it.
- Reach for `assert_*_matches` only when shells legitimately disagree.
  `trace-flag.sh` is the model: dash and bash quote a traced word differently,
  so the case accepts both spellings rather than pinning one shell's output.
- **Always** assert the status, even when you also assert output. Every exit
  code is a documented promise — `README.md` has the table, and which code
  belongs to which failure is decided there, not here — and a case that only
  checks text lets a code regress silently. Look the expected code up; two of
  them are deliberately close together and guessing gets it wrong.

### When a case needs to bypass `run`

Some cases must invoke the runner themselves — piping stdin
(`exec-stdin-is-free`), calling it through a relative path
(`chain-call-relative-path`), or starting the harness again
(`harness-selects-by-name`). Those set `status=$?` by hand, which shellcheck
cannot see through, so they carry a justified disable at the top:

```sh
# $runner and $shell_under_test come from tests/run.sh; $status is read by
# assert_status in tests/lib.sh.
# shellcheck disable=SC2154,SC2034
```

Every `# shellcheck disable=` in this repository explains itself on the line
above. Keep that habit; a bare disable is indistinguishable from a bug.

If a case starts the harness again, it may only select cases that do *not*
themselves start the harness — otherwise the suite recurses.

## When the runner changes

Every behavior change ships with a test, and the order matters:

1. Write the case first and run it. Watch it **fail**, and read the failure —
   a case that passes before the change is testing the wrong thing.
2. Make the change in `spur`.
3. `sh tests/run.sh <the-new-case>` until it is green, then the whole suite.
4. `SPUR_TEST_SHELL=dash sh tests/run.sh` — the real POSIX check.
5. The repository's lint task, if shellcheck is available — and say so when it
   is not.
6. Say out loud whether the change moved the user-facing contract, and hand
   that on. The repository names which document carries which promise and
   requires it to move in the same commit; a case pins behavior, it does not
   get to decide what was promised. Silence here is how a contract and its
   documentation drift apart.

What the suite exists to defend is not decided here. The repository states the
runner's invariants — `AGENTS.md` for how the stages are built, `README.md`
for the half of it users were promised — and the suite's job is to hold them
still. Each already has a case standing on it, and these are the ones to run
first after a refactor that "changes nothing":

| Invariant | Standing on it |
|---|---|
| the runner expands nothing | `assembly-no-expansion-by-runner` |
| dedent keeps a nested block's shape | `assembly-dedent`, `assembly-heredoc-in-body` |
| one `sh -c`: stdin free, errors labelled `spur <task>` | `exec-stdin-is-free`, `exec-error-label` |
| flags stop at the first non-`-` word, and do not group | `exec-argument-passthrough`, `cli-unknown-option` |
| recursion refused, repeated calls allowed | `chain-recursion-detected`, `chain-repeated-call-allowed` |

When a change breaks one of these and the documents still promise it, the case
is right and the change is wrong. That one is not a judgement call to defer:
the promise is on paper, and the case is how it stays true.

## Proposing improvements

Suggesting a better test is welcome and part of the job — but a proposal is
only useful when it is concrete: name the case, say what it would pin, and say
what would break undetected today without it. "Add more edge cases" is noise.

`references/coverage-map.md` holds an audit of what each group pins and a list
of behaviors that are implemented but untested, each with a proposed case
name. Read it when asked about coverage, when adding a case (so you do not
duplicate one), or when you have slack to improve the suite. Verify a gap is
still a gap before proposing it — the file is a snapshot and cases get added.

Good candidates, in rough priority order: an implemented branch no case
reaches (grep every `err(...)` and `die` message against `tests/cases/` — a
message nothing asserts is a branch nothing protects), a documented promise no
case checks, and a flag combination whose interaction is non-obvious.

Before proposing a case for behavior that already works, make sure it is not
vacuous: break the relevant line in a throwaway copy of `spur` and confirm the
case turns red. A case that passes against a mutated runner is pinning
nothing.

Ideas to turn down:

- Anything that adds a dependency or a framework to `tests/`.
- A case that depends on another case, on execution order, or on files outside
  its own directory.
- Coverage for features spur deliberately does not have. The repository fixes
  that scope and lists what falls outside it (`AGENTS.md`, and `README.md` for
  the known limitations). A "test" for something on that list is a redesign in
  disguise, not a coverage gap — turn it down as a scope question, and leave
  the scope itself to the documents that set it.
- Pinning shell-specific output as if it were universal. If dash and bash
  disagree, the case must accept both or it will fail in CI on the shell you
  did not try.
