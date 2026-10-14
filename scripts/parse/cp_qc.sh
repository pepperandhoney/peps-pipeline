#!/usr/bin/env bash
# cp_qc.sh — QC report for a parsed run
#
# USAGE
#   bash cp_qc.sh <RUNDIR> <MHC1|MHC2>
#
# WHAT CHANGED IN v3
#   v2 printed "expected_peptides: SKIPPED". It counted rows but never checked
#   them against anything, so a run that silently produced half its output
#   looked exactly like a complete one. On a campaign that takes a week, that
#   is the failure you most need to catch.
#
#   v3 computes the expected number of rows from the input FASTA, the allele
#   list and the peptide lengths, and compares:
#
#       expected windows at length L = sum over proteins of max(0, len_i - L + 1)
#       expected rows                = sum over L of (windows_L x n_alleles)
#
#   Predictors skip windows containing non-standard residues, so the observed
#   count is normally a little below the expected one. A large shortfall means
#   files are missing or truncated.
#
# EXIT CODES
#   0 everything within tolerance
#   1 a hard problem (no merged TSV, no parsed files)
#   2 completeness below the tolerance -- the report says which check failed
#
# ENVIRONMENT
#   QC_TOLERANCE=95   minimum acceptable completeness, in percent
set -euo pipefail

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
[[ -f "$_d/lib/peps_common.sh" ]] || { echo "ERROR: lib/peps_common.sh not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_d/lib/peps_common.sh"

RUNDIR="${1:?Usage: bash cp_qc.sh <RUNDIR> <MHC1|MHC2>}"
peps_mode_config "${2:?Usage: bash cp_qc.sh <RUNDIR> <MHC1|MHC2>}"
TOL="${QC_TOLERANCE:-95}"

peps_require_dir "$RUNDIR"

RAWDIR="$RUNDIR/raw"
CPDIR="$RUNDIR/cp"
CLEANOUTDIR="$CPDIR/cleanout"
PARSEDIR="$CPDIR/parse"
MERGEDDIR="$CPDIR/merged"
METADIR="$CPDIR/meta"
META="$RUNDIR/meta/run.meta.txt"
QCLOG="$METADIR/cleanparse.qc.txt"
mkdir -p "$METADIR"

meta_get() { [[ -f "$META" ]] && awk -F': *' -v k="^$1:" '$0 ~ k {print $2; exit}' "$META" || true; }

IN_FASTA="$(meta_get input_fasta)"
LENGTHS_META="$(meta_get lengths)"
ALLELES_N="$(meta_get alleles_n)"
[[ -n "$LENGTHS_META" ]] || LENGTHS_META="$(peps_lengths "$MODE")"
[[ -n "$ALLELES_N" ]] || ALLELES_N="$(wc -l < "$RUNDIR/alleles/alleles.txt" 2>/dev/null || echo 0)"

rows_no_header() {
  local n; n="$(wc -l < "$1")"
  (( n > 0 )) && echo $((n - 1)) || echo 0
}

# ---------------------------------------------------------------------------
# Expected counts from the FASTA
# ---------------------------------------------------------------------------
FASTA_PROT=0; FASTA_AA=0; EXPECTED_ROWS=0; EXPECTED_NOTE=""

if [[ -n "$IN_FASTA" && -f "$IN_FASTA" ]]; then
  read -r FASTA_PROT FASTA_AA <<< "$(awk '
    /^>/ { if (L>0) {n++; aa+=L} ; L=0; next }
    { gsub(/[ \t\r\n]/,""); L += length($0) }
    END { if (L>0) {n++; aa+=L}; print n+0, aa+0 }' "$IN_FASTA")"

  EXPECTED_ROWS="$(awk -v lens="$LENGTHS_META" -v na="$ALLELES_N" '
    /^>/ { if (L>0) lenlist[++m]=L; L=0; next }
    { gsub(/[ \t\r\n]/,""); L += length($0) }
    END {
      if (L>0) lenlist[++m]=L
      nl = split(lens, LL, /[ ,]+/)
      total = 0
      for (j = 1; j <= nl; j++) {
        k = LL[j] + 0
        if (k <= 0) continue
        for (i = 1; i <= m; i++) if (lenlist[i] >= k) total += lenlist[i] - k + 1
      }
      printf "%d", total * na
    }' "$IN_FASTA")"
else
  EXPECTED_NOTE="input FASTA not readable; expected counts unavailable"
fi

# ---------------------------------------------------------------------------
# Observed counts
# ---------------------------------------------------------------------------
N_RAW="$(ls -1 "$RAWDIR"/*.out 2>/dev/null | wc -l || echo 0)"
N_CLEAN="$(ls -1 "$CLEANOUTDIR"/*.cleanout 2>/dev/null | wc -l || echo 0)"
N_PARSE="$(ls -1 "$PARSEDIR"/*.tsv 2>/dev/null | wc -l || echo 0)"

N_LENGTHS="$(awk -v s="$LENGTHS_META" 'BEGIN{print split(s, a, /[ ,]+/)}')"
EXPECTED_FILES=$(( ALLELES_N * N_LENGTHS ))

MERGED_TSV=""
[[ -d "$MERGEDDIR" ]] && MERGED_TSV="$(ls -1t "$MERGEDDIR"/*.tsv 2>/dev/null | head -n 1 || true)"
MERGED_ROWS=0
[[ -n "$MERGED_TSV" && -s "$MERGED_TSV" ]] && MERGED_ROWS="$(rows_no_header "$MERGED_TSV")"

pct() { if [[ "${2:-0}" -gt 0 ]]; then echo $(( $1 * 100 / $2 )); else echo 0; fi; }
PCT_FILES="$(pct "$N_PARSE" "$EXPECTED_FILES")"
PCT_ROWS="$(pct "$MERGED_ROWS" "$EXPECTED_ROWS")"

# ---------------------------------------------------------------------------
# Column-level checks on the merged table
# ---------------------------------------------------------------------------
EL_NA_PCT=0; UNIQ_PEP=0; UNIQ_ALLELE=0; UNIQ_LEN=""
if [[ -n "$MERGED_TSV" && -s "$MERGED_TSV" ]]; then
  read -r EL_NA_PCT UNIQ_ALLELE UNIQ_LEN <<< "$(awk -F'\t' '
    NR==1 { for (i=1;i<=NF;i++) h[$i]=i; next }
    { n++
      if (h["%Rank_EL"] && $h["%Rank_EL"]=="NA") na++
      if (h["MHC"])     al[$h["MHC"]]=1
      if (h["Pep_Len"]) pl[$h["Pep_Len"]]=1
    }
    END {
      printf "%d %d ", (n ? na*100/n : 0), length(al)
      sep=""; for (k in pl) { printf "%s%s", sep, k; sep="," }
      printf "\n"
    }' "$MERGED_TSV")"
  UNIQ_PEP="$(awk -F'\t' 'NR==1{for(i=1;i<=NF;i++) if($i=="Peptide") c=i; next} c{print $c}' \
              "$MERGED_TSV" | sort -u | wc -l)"
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
STATUS=0
{
  echo "=== CLEANPARSE QC REPORT ==="
  echo "timestamp : $(peps_utc)"
  echo "rundir    : $RUNDIR"
  echo "mode      : $MODE"
  echo "lengths   : $LENGTHS_META"
  echo "alleles   : $ALLELES_N"
  echo "tolerance : ${TOL}%"
  echo ""

  echo "[1] INPUT"
  echo "  fasta         : ${IN_FASTA:-NOT_RECORDED}"
  echo "  proteins      : $FASTA_PROT"
  echo "  residues      : $FASTA_AA"
  [[ -n "$EXPECTED_NOTE" ]] && echo "  note          : $EXPECTED_NOTE"
  echo ""

  echo "[2] FILE COMPLETENESS"
  echo "  expected      : $EXPECTED_FILES   (alleles x lengths)"
  echo "  raw .out      : $N_RAW"
  echo "  cleanout      : $N_CLEAN"
  echo "  parsed .tsv   : $N_PARSE"
  echo "  completeness  : ${PCT_FILES}%"
  if [[ "$EXPECTED_FILES" -gt 0 && "$PCT_FILES" -lt "$TOL" ]]; then
    echo "  FAIL          : fewer parsed files than expected"
    STATUS=2
  fi
  echo ""

  echo "[3] ROW COMPLETENESS"
  if [[ "$EXPECTED_ROWS" -gt 0 ]]; then
    echo "  expected rows : $EXPECTED_ROWS   (windows x alleles)"
    echo "  merged rows   : $MERGED_ROWS"
    echo "  completeness  : ${PCT_ROWS}%"
    echo "  note          : a small shortfall is normal; predictors skip windows"
    echo "                  containing non-standard residues"
    if [[ "$PCT_ROWS" -lt "$TOL" ]]; then
      echo "  FAIL          : row count below tolerance"
      STATUS=2
    fi
  else
    echo "  merged rows   : $MERGED_ROWS"
    echo "  expected rows : unavailable"
  fi
  echo ""

  echo "[4] MERGED TABLE"
  echo "  file          : ${MERGED_TSV:-NOT_FOUND}"
  echo "  unique peptides: $UNIQ_PEP"
  echo "  unique alleles : $UNIQ_ALLELE  (expected $ALLELES_N)"
  echo "  lengths present: ${UNIQ_LEN:-none}  (expected $LENGTHS_META)"
  echo "  %Rank_EL is NA : ${EL_NA_PCT}% of rows"
  if [[ "${EL_NA_PCT:-0}" -ge 99 ]]; then
    echo "  FAIL          : the eluted-ligand column was not parsed."
    echo "                  The predictor's header spelling is probably unknown"
    echo "                  to the parser. Inspect the top of a raw .out file."
    STATUS=2
  fi
  if [[ "$ALLELES_N" -gt 0 && "${UNIQ_ALLELE:-0}" -lt "$ALLELES_N" ]]; then
    echo "  WARN          : fewer alleles in the table than were requested"
  fi
  echo ""

  echo "[5] PER-FILE ROWS"
  if [[ "$N_PARSE" -gt 0 ]]; then
    for f in "$PARSEDIR"/*.tsv; do
      printf '  %-52s %s\n' "$(basename "$f")" "$(rows_no_header "$f")"
    done | head -n 60
    [[ "$N_PARSE" -gt 60 ]] && echo "  ... and $((N_PARSE - 60)) more"
  else
    echo "  none"
    STATUS=1
  fi
  echo ""

  echo "=== END QC  (status $STATUS) ==="
} > "$QCLOG"

if [[ "$STATUS" -eq 0 ]]; then
  peps_log "QC passed — $QCLOG"
else
  peps_warn "QC reported problems (status $STATUS) — $QCLOG"
  grep -E '^\s+(FAIL|WARN)' "$QCLOG" >&2 || true
fi
exit "$STATUS"
