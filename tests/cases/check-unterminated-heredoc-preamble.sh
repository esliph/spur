# An unterminated heredoc in the preamble is reported once, as the
# preamble's, like any other syntax error there.
spurfile <<'EOF'
cat <<END
never closed

build:
  echo building
EOF

run --check
assert_status 65
assert_stderr_has 'spur (preamble): here-document not terminated'
assert_stderr_lacks 'spur build:'
