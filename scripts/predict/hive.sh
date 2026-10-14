#!/usr/bin/env bash
# hive.sh — massive mode: many proteomes x alleles x lengths through GNU Parallel
#
# WHEN TO USE IT
#   Standard mode (queue.sh -> end2end.sh -> run_NMP_MHC*.sh) walks one proteome
#   at a time and parallelises over alleles. That is the right shape for a
#   handful of proteomes at one peptide length.
#
#   Massive mode flattens the whole campaign into one job list -- every
#   proteome x allele x length combination -- and feeds it to GNU Parallel. Use
#   it when the campaign is large enough that keeping every core busy matters,
#   or when you are running several peptide lengths, where the standard loop
#   would finish one length before starting the next.
#
#   Both modes write the same run_NNN layout and produce the same .out files,
#   so run_cleanparse.sh consumes either without knowing which was used.
#
# USAGE
#   bash hive.sh <MHC1|MHC2> [ORGANISM] [JOBS]
#
#   bash hive.sh MHC1                    # every proteome, cores = nproc
#   bash hive.sh MHC2 leishmania 20      # one organism, 20 parallel jobs
#
# PEPTIDE LENGTHS
#   Taken from peps_lengths(), so the same campaign is described in one place:
#
#     PEPS_LENGTHS_MHC1="8 9 10 11 12 13 14" bash hive.sh MHC1 leishmania 20
#
#   or set MHC1_LENGTHS / MHC2_LENGTHS in configs/lengths.conf.
#
# ENVIRONMENT
#   DRY_RUN=1    build the job list and print it; run nothing
#   FORCE=1      re-run combinations that already have complete output
#   HALT_PCT=10  stop the campaign once this percentage of jobs has failed
#
# RESUMING
#   Re-running hive.sh with the same arguments is safe. Each bee skips work that
#   is already complete, so an interrupted campaign continues where it stopped.
#   Pass RUN_DIR_REUSE=run_003 to write into an existing run instead of a new one.
set -euo pipefail

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
[[ -f "$_d/lib/peps_common.sh" ]] || { echo "ERROR: lib/peps_common.sh not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_d/lib/peps_common.sh"

BEE="$PEPS_SCRIPTS/predict/bee.sh"

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: bash $(basename "$0") <MHC1|MHC2> [ORGANISM] [JOBS]" >&2
  exit 1
fi

MODE_IN="$1"
ORGANISM_FILTER="${2:-}"
JOBS="${3:-$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)}"
HALT_PCT="${HALT_PCT:-10}"

peps_mode_config "$MODE_IN"
peps_require_file "$BEE"
[[ "${DRY_RUN:-0}" == "1" ]] || peps_require_cmd parallel docker

LENGTHS=( $(peps_lengths "$MODE") )
[[ "${#LENGTHS[@]}" -gt 0 ]] || peps_die "no peptide lengths configured for $MODE"

mapfile -t ALLELES < <(peps_read_alleles "$ALLELES_FILE")
[[ "${#ALLELES[@]}" -gt 0 ]] || peps_die "no alleles in $ALLELES_FILE"

mapfile -t KEYS < <(peps_registry_keys "$ORGANISM_FILTER")
[[ "${#KEYS[@]}" -gt 0 ]] || peps_die "no proteomes matched${ORGANISM_FILTER:+ for organism $ORGANISM_FILTER}"

peps_section "HIVE $MODE"
echo "  proteomes : ${#KEYS[@]}${ORGANISM_FILTER:+  (organism: $ORGANISM_FILTER)}"
echo "  alleles   : ${#ALLELES[@]}  ($ALLELES_FILE)"
echo "  lengths   : ${LENGTHS[*]}"
echo "  jobs      : $((${#KEYS[@]} * ${#ALLELES[@]} * ${#LENGTHS[@]}))"
echo "  parallel  : $JOBS"
echo ""

# ---------------------------------------------------------------------------
# One run directory per proteome, created before any bee starts.
#
# Bees run concurrently, so they cannot each allocate a run number: they would
# race on the counter and scatter one campaign across several directories.
# ---------------------------------------------------------------------------
declare -A RUNDIR_OF
for KEY in "${KEYS[@]}"; do
  peps_registry_row "$KEY" || peps_die "key vanished from registry: $KEY"
  BASE_OUT="$(peps_base_out "$PROTEOME_ORGANISM" "$KEY" "$MHC_DIR" "$PROG")"

  if [[ -n "${RUN_DIR_REUSE:-}" ]]; then
    RD="$BASE_OUT/${RUN_DIR_REUSE}"
    [[ -d "$RD" ]] || peps_die "RUN_DIR_REUSE set but not found: $RD"
  else
    RD="$(peps_init_rundir "$BASE_OUT" "$(peps_next_run_id "$BASE_OUT")")"
  fi
  RUNDIR_OF["$KEY"]="$RD"

  IN_FASTA="$(peps_fasta_path "$PROTEOME_INPUT_MODE" "$PROTEOME_FASTA_FILE")"
  printf '%s\n' "${ALLELES[@]}" > "$RD/alleles/alleles.txt"
  peps_write_meta "$RD" \
    "run_dir:      $(basename "$RD")" \
    "timestamp:    $(peps_utc)" \
    "launcher:     hive.sh (massive mode)" \
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
    "parallel:     $JOBS" >/dev/null

  echo "  $KEY -> $RD"
done
echo ""

# ---------------------------------------------------------------------------
# Job list
# ---------------------------------------------------------------------------
JOBLIST="$(mktemp -t peps_hive_XXXXXX)"
trap 'rm -f "$JOBLIST"' EXIT

for KEY in "${KEYS[@]}"; do
  for ALLELE in "${ALLELES[@]}"; do
    for LEN in "${LENGTHS[@]}"; do
      printf '%s\t%s\t%s\t%s\n' "$KEY" "$ALLELE" "$LEN" "${RUNDIR_OF[$KEY]}"
    done
  done
done > "$JOBLIST"

N_JOBS="$(wc -l < "$JOBLIST")"
echo "  job list  : $N_JOBS lines"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  peps_section "DRY RUN — job list"
  head -n 20 "$JOBLIST"
  [[ "$N_JOBS" -gt 20 ]] && echo "  ... and $((N_JOBS - 20)) more"
  exit 0
fi

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
PARALLEL_LOG="${PEPS_PARALLEL_LOG:-$PWD/hive_parallel_$(date -u +%Y%m%d_%H%M%S).log}"

peps_section "START"
peps_log "launching $N_JOBS jobs on $JOBS cores"
echo ""

rc=0
parallel --colsep '\t' \
         -j "$JOBS" \
         --joblog "$PARALLEL_LOG" \
         --halt "soon,fail=${HALT_PCT}%" \
         --line-buffer \
         "FORCE=${FORCE:-0} bash $(printf '%q' "$BEE") $MODE {1} {2} {3} {4}" \
         :::: "$JOBLIST" || rc=$?

peps_section "DONE"
peps_log "parallel exit code: $rc"
echo "  joblog: $PARALLEL_LOG"

if [[ -s "$PARALLEL_LOG" ]]; then
  OK="$(awk 'NR>1 && $7==0' "$PARALLEL_LOG" | wc -l)"
  BAD="$(awk 'NR>1 && $7!=0' "$PARALLEL_LOG" | wc -l)"
  echo "  succeeded: $OK"
  echo "  failed:    $BAD"
  if [[ "$BAD" -gt 0 ]]; then
    echo ""
    echo "  Failed combinations (re-run hive.sh to retry only these):"
    awk -F'\t' 'NR>1 && $7!=0 {print "    " $NF}' "$PARALLEL_LOG" | head -n 20
  fi
fi

echo ""
echo "  Next: bash scripts/parse/run_cleanparse.sh <RUNDIR> $MODE"
exit $rc
