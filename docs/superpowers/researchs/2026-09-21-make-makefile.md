# What `make` and the `Makefile` are and what they are for

## TL;DR
- **`make` is a build automation tool** that reads a text file called `Makefile`, decides what needs to be (re)built by comparing file modification times, and runs the necessary commands — it was created by Stuart Feldman at Bell Labs, first appearing in April 1976, and remains ubiquitous on Unix, Linux and macOS.
- **The `Makefile` describes rules** in the form `target: prerequisites` followed by a *recipe* (commands that must be indented with a TAB); with variables, automatic variables (`$@`, `$<`, `$^`), pattern rules (`%.o: %.c`) and `.PHONY` targets, it expresses a project's dependency graph.
- **It serves far more than compiling C/C++**: it is widely used as a *task runner* (running tests, lint, deploy, generating docs, orchestrating Docker) in Python/Go/JS projects; for large projects there are higher-level generators (Autotools, CMake) and modern alternatives (Ninja, Meson, `just`, Task).

## Key Findings

- **Origin.** `make` was created by Stuart Feldman at Bell Labs, first appearing in April 1976. The classic motivation: a colleague (Steve Johnson, author of yacc) wasted a morning debugging a correct program whose bug had already been fixed — but the file had not been recompiled, and `cc *.o` did not notice. Feldman received the 2003 ACM Software System Award; the official ACM citation reads: *"For MAKE — there is probably no large software system in the world today that has not been processed by a version or offspring of MAKE."*
- **Variants.** The main implementations are GNU make (the most common on Linux, developed by Richard Stallman and Roland McGrath from the late 1980s as part of the GNU Project, maintained since version 3.76 by Paul D. Smith), BSD make (`bmake`/`pmake`, the default on the BSDs), Microsoft's `nmake` (included in Visual Studio) and the make specified by POSIX. The special target `.POSIX` lets you ask for standardized behavior.
- **How it decides what to rebuild.** A target is "out of date" if it does not exist or if it is older than any of its prerequisites (a comparison of last-modification times). This enables *incremental builds*: only what changed is redone.
- **Parallel execution.** The `-j`/`--jobs` option runs several recipes at the same time, respecting the dependency graph; `-l` limits by system load. Many Makefiles fail in parallel because of badly declared dependencies.
- **Pitfalls.** The requirement of a TAB at the start of every recipe line is the most famous gotcha; each recipe line runs in a *separate shell* (so `cd` does not persist between lines); the syntax is cryptic; and there are incompatibilities between GNU and BSD make.
- **Current ecosystem.** For C/C++, CMake now predominates, which *generates* Makefiles (or Ninja files); Ninja is a fast backend; Meson is a modern generator; `just` and Task are *task runners* that fix make's idiosyncrasies.

## Details

### What `make` is

`make` is a command-line build automation tool: it reads a configuration file (the `Makefile`) that describes *what* to build, *what* each thing depends on and *how* to build it, and then automatically decides which parts of a large program need to be recompiled, issuing the commands to do so. The great insight is that `make` is not limited to programs — according to the GNU make manual itself, you can use it to describe any task where some files must be updated automatically from others whenever those change.

**History.** `make` was born out of a concrete frustration. As Feldman related (quoted in *The Art of Unix Programming*), `make` came out of a visit from Steve Johnson, *"storming into my office, cursing the Fates that had caused him to waste a morning debugging a correct program (bug had been fixed, file hadn't been compiled, `cc *.o` was therefore unaffected)"* — that is, storming furiously into Feldman's office after losing a morning debugging a program that was already correct, only because the file had not been recompiled. `make` first appeared in April 1976 at Bell Labs, and spread by being included in Unix (starting with PWB/UNIX). Feldman won the 2003 ACM Software System Award for this contribution.

**Main variants:**
- **GNU make** — the most feature-rich implementation and the most common on Linux; developed by Richard Stallman and Roland McGrath from the late 1980s as part of the GNU Project, maintained since version 3.76 by Paul D. Smith. Conforms to section 6.2 of the IEEE 1003.2 (POSIX.2) standard.
- **BSD make** (`bmake`/`pmake`) — the default on BSD systems; it knows only dependencies, targets, rules and macros, delegating system parameters instead of embedding rules. It is the make used to build the FreeBSD Ports (`bsd.port.mk`).
- **Microsoft nmake** — the "Program Maintenance Utility" included in Visual Studio; similar syntax but incompatible with Unix make, it has to run in a Developer Command Prompt and expands macros at parse time.
- **POSIX make** — the standardized specification (Open Group / IEEE); it is, to a large extent, a subset of the syntaxes accepted by nearly every version. The special target `.POSIX` enables the standardized mode.

### The structure of a `Makefile`

The basic unit is the **rule**:

```makefile
target: prerequisites
	recipe
```

- **Target** — usually the name of a file to be generated (an executable, a `.o`), but it can also be the name of an action (such as `clean`).
- **Prerequisites (dependencies)** — files used as input to create the target. If any prerequisite is newer than the target, the target is considered out of date.
- **Recipe** — one or more lines of commands that `make` runs. **Each recipe line must begin with a TAB character** (or the character defined in `.RECIPEPREFIX`). The GNU make manual is explicit and literal about this: *"you need to put a tab character at the beginning of every recipe line! This is an obscurity that catches the unwary."*

The **default goal** is the first target of the first rule of the first Makefile; that is why it is common to have an `all` target at the top.

**Variables.** They reduce repetition:

```makefile
CC = gcc
CFLAGS = -Wall -O2
```

They are referenced with `$(CC)` or `${CC}`. To pass a literal `$` to the shell, write `$$`.

**Automatic variables** (set by `make` per rule):
- `$@` — the name of the target;
- `$<` — the first prerequisite;
- `$^` — the list of all prerequisites (space-separated);
- `$?` — the prerequisites newer than the target;
- `$*` — the "stem" (the part that matched `%` in a pattern rule).

**Pattern rules.** A pattern rule contains a `%` in the target: `%.o : %.c` says how to make any `file.o` from the corresponding `file.c`. This is the modern form of the old suffix rules.

**Implicit rules and built-in variables.** `make` already ships with implicit rules for common tasks. For example, the built-in recipe for compiling a `.c` is essentially `$(CC) -c $(CFLAGS) $(CPPFLAGS)` — by default `CC = cc`. By redefining `CC` or `CFLAGS` you change the behavior without rewriting the rule. Run `make -p` in a directory with no Makefile to see all the predefined rules and variables.

**`.PHONY` targets.** A *phony* target does not correspond to a real file — it is just a name for a recipe. Declaring `.PHONY: clean` guarantees that `make clean` always runs the recipe even if a file called `clean` exists, and it also improves performance because `make` skips the search for implicit rules. Typical phony targets: `all`, `clean`, `install`, `test`, `lint`.

### How `make` decides what to rebuild

The criterion is simple and timestamp-based: **a target is out of date if it does not exist or if it is older than any of its prerequisites** (a comparison of last-modification times). The idea is that the target's content is computed from the prerequisites; if a prerequisite changes, the existing target stops being valid and must be redone. Because `make` builds a **dependency graph**, it redoes only what was affected by a change — that is the *incremental build*, and it is what makes `make` much faster than recompiling everything.

**Parallel execution (`-j`).** Normally `make` runs one command at a time. With `-j`/`--jobs`, it runs several recipes at once, using the dependency graph to respect the correct order. `make -j` with no number tries to run everything at once (usually not ideal); `make -j8` limits it to 8 jobs. The `-l`/`--max-load` option limits new jobs by the system's load average. The big caveat: parallelism only works if the dependencies are correctly declared — many Makefiles were written assuming serial execution and break (or, worse, produce incorrect binaries) under `-j`.

### What `make` is used for

1. **Compiling C/C++ projects** — the original use case and still the strongest, thanks to pattern rules and automatic dependency tracking.
2. **Task runner** — perhaps the most common use today outside C. Since `make <target>` runs a sequence of commands under a short name, projects in Python, Go, JavaScript and others use Makefiles to standardize `make test`, `make lint`, `make build`, `make deploy`, `make docs`, `make docker-build`, etc. It serves as a single, self-documenting "interface" to the project's commands.
3. **Container and pipeline orchestration** — wrapping `docker build`, `docker compose`, database migrations and CI/CD steps.
4. **Data/science workflows** — running analysis scripts, generating figures and reports (LaTeX, R) only when the input data changes.

### Annotated example: a small C project

```makefile
# Variables: compiler and flags
CC = gcc
CFLAGS = -Wall -Wextra -O2

# List of objects
OBJ = main.o util.o

# Default target (first in the list): the final executable
all: program

# Linking: 'program' depends on the .o files; $@ = program, $^ = all the .o files
program: $(OBJ)
	$(CC) $(CFLAGS) -o $@ $^

# Pattern rule: how to make any %.o from the corresponding %.c
# $< = first prerequisite (the .c); $@ = the target (the .o)
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Utility target with no real file: deletes the artifacts
clean:
	rm -f $(OBJ) program

# Declares targets that are not files
.PHONY: all clean
```

Running it: `make` compiles only what changed; if you edit `util.c`, only `util.o` is recompiled and the program relinked. `make clean` removes the artifacts.

### Annotated example: use as a *task runner* (Python project)

```makefile
.PHONY: install test lint format docker

install:          ## install dependencies
	pip install -r requirements.txt

test:             ## run the test suite
	pytest -q

lint:             ## check style
	ruff check src tests

format:           ## format the code
	black src tests

docker:           ## build the image
	docker build -t myapp:latest .
```

Here no target corresponds to a file — all of them are `.PHONY` — and `make` is used purely to give short, memorable names to frequent commands.

### Common usage commands

- `make` — builds the default target (the first in the Makefile).
- `make <target>` — builds/runs a specific target (e.g. `make test`).
- `make clean` — by convention, removes the build artifacts.
- `make install` — by convention, installs the program; in GNU packages it respects variables such as `prefix` (`make install prefix=/usr`) and `DESTDIR` (`make install DESTDIR=/tmp/stage`) for installs to an alternate location or *staged installs*.
- `make -j8` — parallel build with 8 jobs.
- `make -n` — shows the commands without running them (dry run).
- `make -f file` — uses a Makefile with another name.
- `make -p` — prints the database of built-in rules and variables.

### Related tools and alternatives

- **GNU Autotools (`autoconf`/`automake`)** — a higher-level layer for portability. The developer writes `configure.ac` and `Makefile.am`; `autoconf` generates the `configure` script and `automake` generates `Makefile.in`. When run, `./configure` detects the system and generates the final `Makefile`. Hence the famous trio `./configure && make && make install`.
- **CMake** — today the dominant *meta build system* for C/C++. It reads `CMakeLists.txt` and **generates** Makefiles, Ninja files, Visual Studio projects, etc. It is the reason many existing "Makefiles" are in fact generated.
- **Ninja** — a build backend focused on speed; its `build.ninja` files are not meant to be written by hand — generators such as CMake, Meson and gn produce them. Switching CMake's backend from Make to Ninja usually speeds up builds.
- **Meson** — a modern generator, written in Python, that uses Ninja as its default backend; it focuses on simplicity and only does *out-of-source* builds.
- **Modern task runners** — `just` (written in Rust by Casey Rodarmor; uses a `justfile`, with make-inspired syntax but without the TAB requirement and without implicit rules) and Task (written in Go; uses a YAML `Taskfile.yml`). Both present themselves purely as command runners, not as build systems with a timestamp-based dependency graph.

### Current adoption

In the C/C++ ecosystem, CMake is now overwhelmingly dominant. In the ISO C++ Foundation's *Annual C++ Developer Survey "Lite" 2023* (question "What build tools do you use?", 1,705 responses, check all that apply), the numbers were: **CMake 79.88% (1,362), Ninja 42.93% (732), MSBuild 38.53% (657) and Make/nmake 36.89% (629)**. JetBrains' State of Developer Ecosystem 2019 survey had already recorded CMake's rise: *"Last year CMake beat Visual Studio project to become the most popular project model / build system used for C++ development. Its share has since added 5 percentage points and reached 42%."* Ninja, for its part, has been growing: in JetBrains' 2023 edition, Bryce Adelstein Lelbach (Principal Architect at NVIDIA) commented *"It is very interesting to see CMake drop in market share and Ninja increase... given CMake's rapid growth until now, this data suggests that it has reached peak saturation."* Even so, make remains practically universal (present on every Unix/Linux/macOS) and irreplaceable as a lightweight, dependency-free *task runner*.

## Recommendations

- **To automate a project's commands (test/lint/build/deploy), use `make` as a task runner.** It is universal, already installed, and a 20-line Makefile with `.PHONY` targets documents and standardizes the project. Start there.
  - *Change approach if*: readability becomes a problem for the team, or you need named arguments, native cross-platform support (Windows) or built-in documentation — in that case move to **`just`** (closest to make) or **Task** (YAML). Tip: you can migrate gradually, by having the `Taskfile` call `make` internally.
- **To compile a small/personal C/C++ project, write a Makefile by hand** with pattern rules (`%.o: %.c`) and variables (`CC`, `CFLAGS`). It is educational and sufficient.
  - *Switch to CMake when*: the project has to be portable across compilers/platforms, has many dependencies, or you want to generate IDE projects. CMake generates the Makefiles/Ninja for you; use the Ninja backend for faster builds.
- **Always declare `.PHONY`** for targets that are not files (`all`, `clean`, `test`, `install`) — it avoids bugs if a file of the same name exists and improves performance.
- **Enable parallel builds with `-j`** (e.g. `make -j$(nproc)`), but only after making sure the dependencies are correctly declared; consider testing with race-condition detection tools if the build fails intermittently.
- **For portability**, avoid GNU make-specific extensions if the Makefile has to run on BSD; put `.POSIX` as the first line or let CMake/Autotools generate compatible Makefiles.

## Caveats

- **TAB vs. spaces:** the number one cause of beginner errors. Each recipe line must begin with a literal TAB, not spaces (unless you change `.RECIPEPREFIX`). Editors that convert TAB to spaces break the Makefile.
- **Each line runs in a separate shell:** commands such as `cd` or shell variables do not persist to the next line. Solutions: join commands with `&&` and line continuation (`\`), or use the special target `.ONESHELL`, which passes the whole recipe to a single shell. The official GNU make 3.82 release announcement (July 2010) describes the feature: *"New special target: .ONESHELL instructs make to invoke a single instance of the shell and provide it with the entire recipe, regardless of how many lines it contains."*
- **Cryptic syntax and macros, not variables:** the "variables" of traditional make are macros with recursive evaluation, which can be surprising and, in large projects, degrade performance. GNU make offers immediate assignment (`:=`) to mitigate this.
- **GNU × BSD portability:** simple Makefiles usually work on both, but advanced features (conditionals, functions, `VPATH`, multiple includes) diverge; that is why many Linux projects require `gmake` and BSD projects use `bmake`.
- **`make` on Windows is not native:** it requires WSL, Cygwin, MSYS2 or `nmake` (which has its own incompatible syntax). Modern task runners such as `just`/Task have better cross-platform support.
- **Adoption numbers:** the cited surveys (ISO C++ Foundation and JetBrains) are self-reported and have sampling biases — JetBrains, for example, tends to lean toward users of its own tools, and the two surveys use different question wording. Use them as an indication of a trend, not as an exact measure.
