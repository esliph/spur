spurfile <<'EOF'
build: ## build it
  echo building

## Run the suite. Arguments go straight to the runner:
##   spur test -k login -vv
##
##Uses $TEST_FLAGS when set; nothing here is expanded.
test: ## run the tests
  echo testing
EOF

# The block loses "##" and one space; the rest, indentation included, is
# printed as written. A bare "##" is a blank line. Nothing is executed.
run --describe test
assert_status 0
assert_stdout_is <<'EOF'
test: run the tests

Run the suite. Arguments go straight to the runner:
  spur test -k login -vv

Uses $TEST_FLAGS when set; nothing here is expanded.
EOF
assert_stdout_lacks 'testing'
