#!/usr/bin/env bash
# cp_qc.sh — QC report for cleanparse outputs
# Usage: bash cp_qc.sh <RUNDIR> <LEN>
# Called by run_cleanparse.sh.
set -euo pipefail
export LC_ALL=C

RUNDIR="${1:?ERROR: Provide RUNDIR}"
LEN="${2:?ERROR: Provide LEN (example: 9 or 15 or 14)}"

# Standard dirs
RAWDIR="${RUNDIR}/raw"
CPDIR="${RUNDIR}/cp"
CLEANOUTDIR="${CPDIR}/cleanout"
PARSEDIR="${CPDIR}/parse"
MERGEDDIR="${CPDIR}/merged"
METADIR="${CPDIR}/meta"

QCLOG="${METADIR}/cleanparse.qc.txt"
mkdir -p "$METADIR"

# ------------------------------------------------------------
# Detect merged TSV (newest)
# ------------------------------------------------------------
MERGED_TSV=""
if ls -1 "${MERGEDDIR}"/*.tsv >/dev/null 2>&1; then
  MERGED_TSV="$(ls -1t "${MERGEDDIR}"/*.tsv | head -n 1)"
fi

# ------------------------------------------------------------
# Detect input FASTA
# ------------------------------------------------------------
IN_FASTA=""
if [[ -f "${RUNDIR}/meta/run.meta.txt" ]]; then
  IN_FASTA="$(grep -E '^input_fasta=' "${RUNDIR}/meta/run.meta.txt" 2>/dev/null | cut -d= -f2- || true)"
  if [[ -z "$IN_FASTA" ]]; then
    IN_FASTA="$(grep -E '^input_fasta:' "${RUNDIR}/meta/run.meta.txt" 2>/dev/null | awk -F': *' '{print $2}' || true)"
  fi
fi

# ------------------------------------------------------------
# FASTA stats (sin expected peptides)
# ------------------------------------------------------------
FASTA_PROT_N="NA"
FASTA_AA_TOTAL="NA"
EXPECTED_PEPTIDES="SKIPPED"

if [[ -n "${IN_FASTA:-}" && -f "${IN_FASTA:-}" ]]; then
  FASTA_PROT_N="$(grep -c '^>' "$IN_FASTA" || true)"

  FASTA_AA_TOTAL="$(
    awk '
      BEGIN{aa=0}
      /^>/ {next}
      {gsub(/[ \t\r\n]/,""); aa += length($0)}
      END{print aa}
    ' "$IN_FASTA"
  )"
fi

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
rows_no_header() {
  local f="$1"
  local n
  n="$(wc -l < "$f")"
  if [[ "$n" -gt 0 ]]; then
    echo $((n-1))
  else
    echo 0
  fi
}

# ------------------------------------------------------------
# QC report
# ------------------------------------------------------------
{
  echo "=== CLEANPARSE QC REPORT ==="
  echo "timestamp: $(date)"
  echo "RUNDIR:    $RUNDIR"
  echo "LEN:       $LEN"
  echo

  echo "[1] COUNTS"
  echo "raw_out_files:        $(ls -1 "$RAWDIR"/*.out 2>/dev/null | wc -l || true)"
  echo "cleanout_files:       $(ls -1 "$CLEANOUTDIR"/*.cleanout 2>/dev/null | wc -l || true)"
  echo "parsed_tsv_files:     $(ls -1 "$PARSEDIR"/*.tsv 2>/dev/null | wc -l || true)"
  echo "merged_tsv:           ${MERGED_TSV:-NOT_FOUND}"
  echo

  echo "[2] RAW OUT QC"
  if ls -1 "$RAWDIR"/*.out >/dev/null 2>&1; then
    for f in "$RAWDIR"/*.out; do
      echo "$(basename "$f")  lines=$(wc -l < "$f")  size=$(wc -c < "$f")"
    done
  else
    echo "ERROR: no raw .out files found"
  fi
  echo

  echo "[3] PARSED TSV QC"
  missing_peptide_col=0
  if ls -1 "$PARSEDIR"/*.tsv >/dev/null 2>&1; then
    for f in "$PARSEDIR"/*.tsv; do
      if ! head -n 1 "$f" | tr '\t' '\n' | grep -qx "Peptide"; then
        missing_peptide_col=$((missing_peptide_col+1))
      fi
      echo "$(basename "$f") rows=$(rows_no_header "$f")"
    done
  else
    echo "ERROR: no parsed TSV"
  fi
  echo "missing Peptide headers: $missing_peptide_col"
  echo

  echo "[4] MERGED TSV QC"
  if [[ -n "${MERGED_TSV:-}" && -s "${MERGED_TSV:-}" ]]; then
    echo "merged_lines_total: $(wc -l < "$MERGED_TSV")"
    echo "merged_rows_no_header: $(rows_no_header "$MERGED_TSV")"
  else
    echo "ERROR: merged TSV missing"
  fi
  echo

  echo "[5] FASTA STATS"
  echo "input_fasta: $IN_FASTA"
  echo "fasta_proteins: $FASTA_PROT_N"
  echo "fasta_total_aa: $FASTA_AA_TOTAL"
  echo "expected_peptides: $EXPECTED_PEPTIDES"
  echo

  echo "=== END QC ==="
} > "$QCLOG"

echo "QC report written to: $QCLOG"
