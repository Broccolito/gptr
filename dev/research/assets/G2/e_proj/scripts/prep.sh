#!/bin/sh
set -e
in=$1; out=$2
mkdir -p "$out"
for f in "$in"/*.csv; do
  n=$(wc -l < "$f")
  echo "$(basename "$f"): $n lines"
  cp "$f" "$out"/
done
echo done
