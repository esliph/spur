spurfile <<'EOF'
zebra: ## last alphabetically, first in the file
  echo z

alpha: ## first alphabetically, last in the file
  echo a
EOF

run
assert_status 0
assert_stdout_is <<EOF
Spurfile: $PWD/Spurfile

  zebra   last alphabetically, first in the file
  alpha   first alphabetically, last in the file
EOF
