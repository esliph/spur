# The baseline: end-to-end latency of a task that only echoes.
printf 'hello:\n  echo hello\n' >Spurfile
measure hello
