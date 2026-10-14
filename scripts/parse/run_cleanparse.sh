#!/usr/bin/env bash
# run_cleanparse.sh — turn raw predictor output into one analysis-ready TSV
#
# PIPELINE
#   raw/*.out  --cp_cleanout.awk-->  cp/cleanout/*.cleanout
#              --cp_parse_*.awk--->  cp/parse/*.tsv      (one per allele x length)
#              --cp_mergetsv.sh--->  cp/merged/merged_mhc{1,2}.tsv
#              --cp_qc.sh-------->  cp/meta/cleanparse.qc.txt
#
# USAGE
#   bash run_cleanparse.sh <RUNDIR> <MHC1|MHC2> [DATASET]
#
#   bash run_cleanparse.sh /data/out/leishmania/.../run_001 MHC1
#
#   LEN is no longer an argument. v2 took it so the QC could compute expected
#   peptide counts, but a multilength run has no single length; cp_qc.sh now
#   reads the lengths from the run metadata instead.
#
# ENVIRONMENT
#   SKIP_QC=1   skip the QC report
set -euo pipefail
trap 'shopt -u nullglob 2>/dev/null || true' EXIT

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
[[ -f "$_d/lib/peps_common.sh" ]] || { echo "ERROR: lib/peps_common.sh not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_d/lib/peps_common.sh"

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: bash $(basename "$0") <RUNDIR> <MHC1|MHC2> [DATASET]" >&2
  exit 1
fi

RUNDIR="$1"
peps_mode_config "$2"
DATASET="${3:-}"

peps_require_dir "$RUNDIR"

RAWDIR="$RUNDIR/raw"
CPDIR="$RUNDIR/cp"
CLEANOUTDIR="$CPDIR/cleanout"
PARSEDIR="$CPDIR/parse"
MERGEDDIR="$CPDIR/merged"
METADIR="$CPDIR/meta"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWK_CLEAN="$HERE/cp_cleanout.awk"
MERGE_SCRIPT="$HERE/cp_mergetsv.sh"
QC_SCRIPT="$HERE/cp_qc.sh"

case "$MODE" in
  MHC1) AWK_PARSE="$HERE/cp_parse_NMP_MHC1_4.2.awk"; MERGED_TSV="$MERGEDDIR/merged_mhc1.tsv" ;;
  MHC2) AWK_PARSE="$HERE/cp_parse_NMP_MHC2_4.3.awk"; MERGED_TSV="$MERGEDDIR/merged_mhc2.tsv" ;;
esac

peps_require_dir "$RAWDIR"
peps_require_file "$AWK_CLEAN" "$AWK_PARSE" "$MERGE_SCRIPT" "$QC_SCRIPT"

# The dataset label identifies rows once several proteomes sit in one table.
# It comes from the run metadata so it cannot drift from the registry prefix,
# which is what produced Lpanv2_mhc1 / Lpan_v1 / Lpanv1 for one proteome in v1.
if [[ -z "$DATASET" && -f "$RUNDIR/meta/run.meta.txt" ]]; then
  DATASET="$(awk -F': *' '/^prefix:/{print $2; exit}' "$RUNDIR/meta/run.meta.txt")"
  [[ -n "$DATASET" ]] && DATASET="${DATASET}_$(printf '%s' "$MODE" | tr '[:upper:]' '[:lower:]')"
fi
DATASET="${DATASET:-$(basename "$RUNDIR")}"

mkdir -p "$CLEANOUTDIR" "$PARSEDIR" "$MERGEDDIR" "$METADIR"

peps_section "CLEANPARSE  $MODE"
echo "  rundir  : $RUNDIR"
echo "  dataset : $DATASET"

shopt -s nullglob
OUTFILES=( "$RAWDIR"/*.out )
shopt -u nullglob
[[ "${#OUTFILES[@]}" -gt 0 ]] || peps_die "no .out files in $RAWDIR"
echo "  raw     : ${#OUTFILES[@]} files"

# --- clean -----------------------------------------------------------------
peps_log "cleaning"
for f in "${OUTFILES[@]}"; do
  base="$(basename "$f" .out)"
  awk -v mode="$MODE" \
      -v clean="$CLEANOUTDIR/$base.cleanout" \
      -v meta="$CLEANOUTDIR/${base}_meta.txt" \
      -f "$AWK_CLEAN" "$f"
done

shopt -s nullglob
CLEANFILES=( "$CLEANOUTDIR"/*.cleanout )
shopt -u nullglob
[[ "${#CLEANFILES[@]}" -gt 0 ]] || peps_die "no .cleanout produced in $CLEANOUTDIR"

# --- parse -----------------------------------------------------------------
peps_log "parsing ${#CLEANFILES[@]} files"
PARSE_FAILED=0
for c in "${CLEANFILES[@]}"; do
  base="$(basename "$c" .cleanout)"
  if ! awk -v dataset="$DATASET" -v out="$PARSEDIR/$base.tsv" -f "$AWK_PARSE" "$c"; then
    peps_warn "parse failed: $base"
    PARSE_FAILED=$((PARSE_FAILED + 1))
  fi
done
[[ "$PARSE_FAILED" -eq 0 ]] || peps_warn "$PARSE_FAILED file(s) failed to parse"

shopt -s nullglob
PARSEFILES=( "$PARSEDIR"/*.tsv )
shopt -u nullglob
[[ "${#PARSEFILES[@]}" -gt 0 ]] || peps_die "no .tsv produced in $PARSEDIR"

# --- merge -----------------------------------------------------------------
peps_log "merging"
bash "$MERGE_SCRIPT" "$PARSEDIR" "$MERGED_TSV"

# --- sanity check on the eluted-ligand column ------------------------------
# An all-NA %Rank_EL means the parser did not recognise the header spelling.
# Catching it here costs one pass over a few thousand rows; catching it after a
# week-long campaign costs the campaign.
if [[ -s "$MERGED_TSV" ]]; then
  EL_NA="$(awk -F'\t' '
    NR==1 {for (i=1;i<=NF;i++) if ($i=="%Rank_EL") c=i; next}
    c && $c=="NA" {na++} {n++}
    END {if (n>0) printf "%d", na*100/n; else print 0}' "$MERGED_TSV")"
  if [[ "${EL_NA:-0}" -ge 99 ]]; then
    peps_warn "%Rank_EL is NA in ${EL_NA}% of rows."
    peps_warn "The predictor's header spelling is probably not one the parser knows."
    peps_warn "Inspect: head -n 30 ${OUTFILES[0]}"
  fi
fi

# --- QC --------------------------------------------------------------------
if [[ "${SKIP_QC:-0}" == "1" ]]; then
  peps_log "QC skipped (SKIP_QC=1)"
else
  bash "$QC_SCRIPT" "$RUNDIR" "$MODE"
fi

{
  echo "timestamp: $(peps_utc)"
  echo "rundir:    $RUNDIR"
  echo "mode:      $MODE"
  echo "dataset:   $DATASET"
  echo "raw_files: ${#OUTFILES[@]}"
  echo "parsed:    ${#PARSEFILES[@]}"
  echo "merged:    $MERGED_TSV"
  echo "pipeline:  peps-pipeline v3"
} > "$METADIR/cleanparse.meta.txt"

echo ""
echo "  parse  : $PARSEDIR"
echo "  merged : $MERGED_TSV"
echo "  qc     : $METADIR/cleanparse.qc.txt"
