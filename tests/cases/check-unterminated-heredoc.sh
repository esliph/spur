# sh -n accepts a heredoc that runs to the end of the script (dash says
# nothing, bash only warns), so --check has to catch it on its own.
spurfile <<'EOF'
ok:
  cat <<END
  closed
  END

broken:
  cat <<END
  never closed
EOF

run --check
assert_status 65
assert_stderr_has 'spur broken: here-document not terminated'
assert_stderr_has "spur: run 'spur -n broken' to see the assembled script"
assert_stderr_lacks 'spur ok:'
assert_stderr_lacks "'spur -n ok'"

run --check ok
assert_status 0
