#!/usr/bin/env bash
# bee.sh — a single prediction unit: one proteome x one allele x one length
#
# WHAT IT IS
#   The smallest restartable piece of work in the pipeline. One bee runs one
#   container, writes one .out and one .err, and exits. It is normally invoked
#   by hive.sh through GNU Parallel, but it runs perfectly well on its own when
#   you want to retry a single failed combination.
#
#   Standard mode (run_NMP_MHC1.sh / run_NMP_MHC2.sh) covers one proteome at a
#   time and manages its own run directory. Massive mode (hive.sh + bee.sh) is
#   for campaigns that span many proteomes, alleles and lengths at once; hive
#   creates the run directories and hands each bee the one it should write to.
#
# USAGE
#   bash bee.sh <MHC1|MHC2> <PROTEOME_KEY> <ALLELE> <LENGTH> <RUNDIR>
#
#   bash bee.sh MHC1 LAET HLA-A03:01 9  /data/out/leishmania/.../run_001
#   bash bee.sh MHC2 LAET DRB1_0701  15 /data/out/leishmania/.../run_001
#
# ENVIRONMENT
#   DRY_RUN=1      print the command instead of running it (no Docker needed)
#   FORCE=1        re-run even when a complete output already exists
#   PEPS_SORT=1    pass -s to NetMHCpan (off by default; sorting a proteome-wide
#                  output costs memory and nothing downstream depends on it)
#
# EXIT CODES
#   0 success, or the output already existed and was complete
#   1 usage or configuration error
#   2 the predictor itself failed (see the .err file)
set -euo pipefail

# Locate the repository root by walking up until lib/peps_common.sh appears.
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
[[ -f "$_d/lib/peps_common.sh" ]] || { echo "ERROR: lib/peps_common.sh not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_d/lib/peps_common.sh"

if [[ $# -ne 5 ]]; then
  echo "Usage: bash $(basename "$0") <MHC1|MHC2> <PROTEOME_KEY> <ALLELE> <LENGTH> <RUNDIR>" >&2
  exit 1
fi

MODE_IN="$1"; KEY="$2"; ALLELE="$3"; LEN="$4"; RUNDIR="$5"

peps_mode_config "$MODE_IN"
peps_registry_row "$KEY" || peps_die "proteome key not in registry: $KEY"

[[ "$LEN" =~ ^[0-9]+$ ]] || peps_die "length must be an integer (got: $LEN)"
peps_require_dir "$RUNDIR"

IN_FASTA="$(peps_fasta_path "$PROTEOME_INPUT_MODE" "$PROTEOME_FASTA_FILE")"
peps_require_file "$IN_FASTA"

PREFIX="${PROTEOME_PREFIX}_$(printf '%s' "$MODE" | tr '[:upper:]' '[:lower:]')"
BASENAME="$(peps_out_basename "$PREFIX" "$ALLELE" "$LEN")"
OUT="$RUNDIR/raw/$BASENAME.out"
ERR="$RUNDIR/err/$BASENAME.err"
mkdir -p "$RUNDIR/raw" "$RUNDIR/err" "$RUNDIR/logs"

LOG="$RUNDIR/logs/bee.log"

# ---------------------------------------------------------------------------
# Skip when this combination is already done.
#
# A complete NetMHC output always contains a "# Rank" line. Checking for it
# distinguishes a finished file from one left half written by an interrupted
# run, which a plain -f test would wrongly accept.
# ---------------------------------------------------------------------------
if [[ "${FORCE:-0}" != "1" && -s "$OUT" ]] && grep -q '^# Rank' "$OUT" 2>/dev/null; then
  peps_log "SKIP  $KEY $ALLELE len$LEN (already complete)" | tee -a "$LOG"
  exit 0
fi

# ---------------------------------------------------------------------------
# Build the predictor command. The two tools differ in their flags, so this is
# the one place that knows about both.
# ---------------------------------------------------------------------------
case "$MODE" in
  MHC1)
    TOOL_ARGS=( -a "$ALLELE" -f "$IN_FASTA" -inptype 0 -l "$LEN" -BA )
    [[ "${PEPS_SORT:-0}" == "1" ]] && TOOL_ARGS+=( -s )
    CMD=( "$TOOL" "${TOOL_ARGS[@]}" )
    ;;
  MHC2)
    CMD=( "$TOOL" -rdir "$RDIR" -f "$IN_FASTA" -a "$ALLELE" -inptype 0 -length "$LEN" -BA )
    ;;
esac

# Quote every argument so the string is safe inside bash -lc.
CMD_STR="$(printf '%q ' "${CMD[@]}")"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN docker run --rm --user $(id -u):$(id -g) \\"
  echo "        -v $PEPS_DATA_IN:$PEPS_DATA_IN:ro -v $PEPS_DATA_OUT:$PEPS_DATA_OUT \\"
  echo "        $IMAGE bash -lc \"$CMD_STR > $OUT 2> $ERR\""
  exit 0
fi

peps_require_cmd docker

peps_log "START $KEY $ALLELE len$LEN" | tee -a "$LOG"

rc=0
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$PEPS_DATA_IN:$PEPS_DATA_IN:ro" \
  -v "$PEPS_DATA_OUT:$PEPS_DATA_OUT" \
  "$IMAGE" \
  bash -lc "set -euo pipefail; export TMPDIR=/tmp; $CMD_STR > $(printf '%q' "$OUT") 2> $(printf '%q' "$ERR")" \
  || rc=$?

if [[ $rc -ne 0 ]]; then
  peps_warn "FAILED $KEY $ALLELE len$LEN (exit $rc) — see $ERR"
  peps_log "FAIL  $KEY $ALLELE len$LEN exit=$rc" >> "$LOG"
  exit 2
fi

# A command that exits 0 but writes an unusable file is worse than one that
# fails loudly, so verify the output before declaring success.
if ! grep -q '^# Rank' "$OUT" 2>/dev/null; then
  peps_warn "SUSPECT $KEY $ALLELE len$LEN — exit 0 but no '# Rank' line in $OUT"
  peps_log "SUSPECT $KEY $ALLELE len$LEN" >> "$LOG"
  exit 2
fi

peps_log "DONE  $KEY $ALLELE len$LEN" | tee -a "$LOG"
