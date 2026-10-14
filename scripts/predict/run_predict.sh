#!/usr/bin/env bash
# run_predict.sh — standard mode: one proteome, every allele, every length
#
# WHAT IT IS
#   The default runner. It creates the run directory, writes the metadata, and
#   works through the allele x length grid with a bounded number of concurrent
#   jobs. Each job is a bee, the same execution unit massive mode uses, so both
#   modes produce byte-identical outputs and the parser cannot tell them apart.
#
#   v2 had two near-identical runners, run_NMP_MHC1.sh and run_NMP_MHC2.sh,
#   which differed only in the flags passed to the container. Those flags now
#   live in peps_mode_config() and bee.sh, so there is one runner and the
#   per-tool knowledge sits in one place. The old names remain as wrappers.
#
# USAGE
#   bash run_predict.sh <MHC1|MHC2> <PROTEOME_KEY>
#
#   bash run_predict.sh MHC1 LAET
#   PEPS_LENGTHS_MHC1="8 9 10 11 12 13 14" bash run_predict.sh MHC1 LAET
#
# ENVIRONMENT
#   MAX_PARALLEL=6   concurrent containers (default 6)
#   DRY_RUN=1        print the commands, run nothing
#   FORCE=1          re-run combinations that already completed
#
# OUTPUT
#   $PEPS_DATA_OUT/<organism>/prediction/<key>/<MHC1|MHC2>/<prog>/run_NNN/
#   The path of the run directory is printed on the last line, so a caller can
#   capture it:  RUNDIR="$(bash run_predict.sh MHC1 LAET | tail -n 1)"
set -euo pipefail

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
[[ -f "$_d/lib/peps_common.sh" ]] || { echo "ERROR: lib/peps_common.sh not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_d/lib/peps_common.sh"

BEE="$PEPS_SCRIPTS/predict/bee.sh"
MAX_PARALLEL="${MAX_PARALLEL:-6}"

if [[ $# -ne 2 ]]; then
  echo "Usage: bash $(basename "$0") <MHC1|MHC2> <PROTEOME_KEY>" >&2
  exit 1
fi

MODE_IN="$1"; KEY="$2"

peps_mode_config "$MODE_IN"
peps_registry_row "$KEY" || peps_die "proteome key not in registry: $KEY"
peps_require_file "$BEE"

IN_FASTA="$(peps_fasta_path "$PROTEOME_INPUT_MODE" "$PROTEOME_FASTA_FILE")"
peps_require_file "$IN_FASTA"

LENGTHS=( $(peps_lengths "$MODE") )
mapfile -t ALLELES < <(peps_read_alleles "$ALLELES_FILE")
[[ "${#ALLELES[@]}" -gt 0 ]] || peps_die "no alleles in $ALLELES_FILE"

BASE_OUT="$(peps_base_out "$PROTEOME_ORGANISM" "$KEY" "$MHC_DIR" "$PROG")"
RUN_PAD="$(peps_next_run_id "$BASE_OUT")"
RUNDIR="$(peps_init_rundir "$BASE_OUT" "$RUN_PAD")"

printf '%s\n' "${ALLELES[@]}" > "$RUNDIR/alleles/alleles.txt"
peps_write_meta "$RUNDIR" \
  "run_dir:      run_$RUN_PAD" \
  "timestamp:    $(peps_utc)" \
  "launcher:     run_predict.sh (standard mode)" \
  "image:        $IMAGE" \
  "tool:         $TOOL" \
  "proteome:     $KEY" \
  "organism:     $PROTEOME_ORGANISM" \
  "input_fasta:  $IN_FASTA" \
  "input_mode:   $PROTEOME_INPUT_MODE" \
  "mode:         $MODE" \
  "lengths:      ${LENGTHS[*]}" \
  "alleles_n:    ${#ALLELES[@]}" \
  "prefix:       ${PROTEOME_PREFIX}" \
  "max_parallel: $MAX_PARALLEL" >/dev/null

peps_section "$MODE  $KEY"
echo "  organism : $PROTEOME_ORGANISM"
echo "  fasta    : $IN_FASTA"
echo "  alleles  : ${#ALLELES[@]}"
echo "  lengths  : ${LENGTHS[*]}"
echo "  jobs     : $(( ${#ALLELES[@]} * ${#LENGTHS[@]} ))"
echo "  rundir   : $RUNDIR"
echo ""

RUNLOG="$RUNDIR/logs/runner.log"
peps_log "START" | tee -a "$RUNLOG"

# Wait until a slot frees up. `jobs -rp` lists only running background jobs of
# this shell, so the count is exact even when some have already finished.
wait_for_slot() {
  while [[ "$(jobs -rp | wc -l)" -ge "$MAX_PARALLEL" ]]; do sleep 1; done
}

declare -A JOB_LABEL
trap 'peps_warn "interrupted; waiting for running jobs"; wait || true; exit 130' INT TERM

for ALLELE in "${ALLELES[@]}"; do
  for LEN in "${LENGTHS[@]}"; do
    wait_for_slot
    DRY_RUN="${DRY_RUN:-0}" FORCE="${FORCE:-0}" \
      bash "$BEE" "$MODE" "$KEY" "$ALLELE" "$LEN" "$RUNDIR" >>"$RUNLOG" 2>&1 &
    JOB_LABEL[$!]="$ALLELE len$LEN"
  done
done

FAILED=0
for pid in "${!JOB_LABEL[@]}"; do
  if ! wait "$pid"; then
    peps_warn "FAILED: ${JOB_LABEL[$pid]}"
    FAILED=$((FAILED + 1))
  fi
done

peps_log "DONE  failures=$FAILED" | tee -a "$RUNLOG"

if [[ "$FAILED" -gt 0 ]]; then
  peps_warn "$FAILED of $(( ${#ALLELES[@]} * ${#LENGTHS[@]} )) jobs failed; see $RUNDIR/err/"
  peps_warn "re-run the same command to retry only the failures"
  echo "$RUNDIR"
  exit 1
fi

echo ""
echo "  raw : $RUNDIR/raw"
echo "  log : $RUNLOG"
echo "$RUNDIR"
