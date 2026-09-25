# The upward search: the Spurfile is ten directories above the caller.
printf 'hello:\n  echo hello\n' >Spurfile
mkdir -p a/b/c/d/e/f/g/h/i/j
cd a/b/c/d/e/f/g/h/i/j || exit 1
measure hello
