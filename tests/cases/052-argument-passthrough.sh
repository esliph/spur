spurfile <<'EOF'
show:
  printf 'count=%s\n' "$#"
  for a in "$@"; do printf 'arg=[%s]\n' "$a"; done
EOF

run show -k foo "two words" -vv
assert_status 0
assert_stdout_is <<'EOF'
count=4
arg=[-k]
arg=[foo]
arg=[two words]
arg=[-vv]
EOF
