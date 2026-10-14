#!/usr/bin/env bash
# cp_mergetsv.sh — Merge per-allele TSVs into a single file
# Usage: bash cp_mergetsv.sh <INPUT_DIR> <OUTPUT_FILE>
# Called by run_cleanparse.sh.
set -euo pipefail

IN_DIR="${1:-.}"
OUT_FILE="${2:-merged_mhc2.tsv}"

mkdir -p "$(dirname "$OUT_FILE")"
rm -f "$OUT_FILE"

shopt -s nullglob
files=( "$IN_DIR"/*.tsv )
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "ERROR: no .tsv files found in $IN_DIR" >&2
  exit 1
fi

IFS=$'\n' sorted=($(printf '%s\n' "${files[@]}" | sort))
first="${sorted[0]}"

header="$(head -n1 "$first")"
echo "$header" > "$OUT_FILE"

for f in "${sorted[@]}"; do
  if [[ "$(head -n1 "$f")" != "$header" ]]; then
    echo "WARNING: header mismatch in $f — skipping" >&2
    continue
  fi
  tail -n +2 "$f" >> "$OUT_FILE"
done

echo "Merged TSV created: $OUT_FILE"
echo "Input dir: $IN_DIR"