#!/usr/bin/env bash
# run_cleanparse.sh — Clean, parse, merge and QC prediction outputs
# Usage: bash run_cleanparse.sh <RUNDIR> <MODE> <LEN> [DATASET]
# Example: bash run_cleanparse.sh /data/out/.../run_001 MHC1 9
# Called by end2end.sh.
set -euo pipefail
trap 'shopt -u nullglob' EXIT

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: bash $(basename "$0") <RUNDIR> <MODE> <LEN> [DATASET]" >&2
  exit 1
fi

RUNDIR="$1"
MODE_RAW="$2"
LEN="$3"
DATASET="${4:-}"

MODE="$(echo "$MODE_RAW" | tr '[:lower:]' '[:upper:]')"

RAWDIR="${RUNDIR}/raw"
CPDIR="${RUNDIR}/cp"
CLEANOUTDIR="${CPDIR}/cleanout"
PARSEDIR="${CPDIR}/parse"
MERGEDDIR="${CPDIR}/merged"
METADIR="${CPDIR}/meta"

AWK_CLEAN="$HOME/scripts/cp_cleanout.awk"
QC_SCRIPT="$HOME/scripts/cp_qc.sh"
MERGE_SCRIPT="$HOME/scripts/cp_mergetsv.sh"

case "$MODE" in
  MHC1)
    AWK_PARSE="$HOME/scripts/cp_parse_NMP_MHC1_4.2.awk"
    MERGED_TSV="${MERGEDDIR}/merged_mhc1.tsv"
    ;;
  MHC2)
    AWK_PARSE="$HOME/scripts/cp_parse_NMP_MHC2_4.3.awk"
    MERGED_TSV="${MERGEDDIR}/merged_mhc2.tsv"
    ;;
  *)
    echo "ERROR: MODE must be MHC1 or MHC2" >&2
    exit 1
    ;;
esac

[[ -d "$RAWDIR" ]] || { echo "ERROR: raw/ not found: $RAWDIR" >&2; exit 1; }
[[ -f "$AWK_CLEAN" ]] || { echo "ERROR: missing $AWK_CLEAN" >&2; exit 1; }
[[ -f "$AWK_PARSE" ]] || { echo "ERROR: missing $AWK_PARSE" >&2; exit 1; }
[[ -f "$MERGE_SCRIPT" ]] || { echo "ERROR: missing $MERGE_SCRIPT" >&2; exit 1; }
[[ -f "$QC_SCRIPT" ]] || { echo "ERROR: missing $QC_SCRIPT" >&2; exit 1; }

if [[ -z "$DATASET" && -f "${RUNDIR}/meta/run.meta.txt" ]]; then
  DATASET="$(awk -F': *' '/^prefix:/{print $2; exit}' "${RUNDIR}/meta/run.meta.txt")"
fi
DATASET="${DATASET:-$(basename "$RUNDIR")}"

mkdir -p "$CLEANOUTDIR" "$PARSEDIR" "$MERGEDDIR" "$METADIR"

shopt -s nullglob
OUTFILES=( "$RAWDIR"/*.out )
shopt -u nullglob

[[ "${#OUTFILES[@]}" -gt 0 ]] || { echo "ERROR: no .out files found in $RAWDIR" >&2; exit 1; }

for f in "${OUTFILES[@]}"; do
  base="$(basename "$f" .out)"

  awk -v mode="$MODE" \
      -v clean="${CLEANOUTDIR}/${base}.cleanout" \
      -v meta="${CLEANOUTDIR}/${base}_meta.txt" \
      -f "$AWK_CLEAN" "$f"
done

shopt -s nullglob
CLEANFILES=( "$CLEANOUTDIR"/*.cleanout )
shopt -u nullglob

[[ "${#CLEANFILES[@]}" -gt 0 ]] || { echo "ERROR: no .cleanout files produced in $CLEANOUTDIR" >&2; exit 1; }

for c in "${CLEANFILES[@]}"; do
  base="$(basename "$c" .cleanout)"

  awk -v dataset="$DATASET" \
      -v out="${PARSEDIR}/${base}.tsv" \
      -f "$AWK_PARSE" "$c"
done

shopt -s nullglob
PARSEFILES=( "$PARSEDIR"/*.tsv )
shopt -u nullglob
[[ "${#PARSEFILES[@]}" -gt 0 ]] || { echo "ERROR: no .tsv files produced in $PARSEDIR" >&2; exit 1; }

bash "$MERGE_SCRIPT" "$PARSEDIR" "$MERGED_TSV"
bash "$QC_SCRIPT" "$RUNDIR" "$LEN"

PARSE_META="${METADIR}/cleanparse.meta.txt"
{
  echo "timestamp: $(date -u +%Y%m%d_%H%M%S) (UTC)"
  echo "rundir:    $RUNDIR"
  echo "mode:      $MODE"
  echo "dataset:   $DATASET"
  echo "length:    $LEN"
  echo "rawdir:    $RAWDIR"
  echo "cleanout:  $CLEANOUTDIR"
  echo "parse:     $PARSEDIR"
  echo "merged:    $MERGED_TSV"
} > "$PARSE_META"

echo "DONE."
echo "CLEANOUT: $CLEANOUTDIR"
echo "PARSE:    $PARSEDIR"
echo "MERGED:   $MERGED_TSV"
echo "QC:       ${METADIR}/cleanparse.qc.txt"
echo "META:     $PARSE_META"
