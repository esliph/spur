# "sh spur build" runs ./spur, so a chained spur must be ./spur too, even
# when another spur sits on PATH.
# $runner and $shell_under_test come from tests/run.sh.
# shellcheck disable=SC2154
spurfile <<'EOF'
build:
  echo "$SPUR_BIN"
  spur deps

deps:
  echo installing deps
EOF

cp "$runner" ./spur
mkdir decoy
printf '#!/bin/sh\necho decoy\n' >decoy/spur
chmod +x decoy/spur

base=$PWD
capture env PATH="$PWD/decoy:$PATH" "$shell_under_test" spur build
assert_status 0
assert_stdout_is <<EOF
$base/spur
installing deps
EOF
