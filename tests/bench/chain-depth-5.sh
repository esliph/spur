# spur calling spur: five runner starts, each task calling the next.
cat >Spurfile <<'EOF'
l1:
  spur l2
l2:
  spur l3
l3:
  spur l4
l4:
  spur l5
l5:
  echo bottom
EOF
measure l1
