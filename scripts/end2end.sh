#!/usr/bin/env bash
# end2end.sh — everything for one proteome: predict, parse, annotate, archive
#
# WHAT IT DOES
#   1. prediction      run_predict.sh (or hive.sh with --massive)
#   2. clean + parse   run_cleanparse.sh  -> merged TSV
#   3. annotate        pp_annotate.sh     -> original accessions restored
#   4. backup          gs_backupbucket.sh (skippable)
#   5. cleanup         gs_cleandisk.sh    (skippable)
#
#   Step 3 is new in v3. v2 shipped pp_annotate.sh but never called it, so the
#   merged TSV kept the short identifiers and the accession had to be restored
#   by hand -- which is easy to forget and makes the output look as though the
#   protein of origin had been lost.
#
# USAGE
#   bash end2end.sh <MHC1|MHC2> <PROTEOME_KEY> [--massive] [--jobs N]
#
#   bash end2end.sh MHC1 LAET
#   bash end2end.sh MHC2 LAET --massive --jobs 20
#
# ENVIRONMENT
#   SKIP_BACKUP=1   do not upload to Google Cloud Storage
#   SKIP_CLEAN=1    keep raw/, err/ and cleanout/ on local disk
#   SKIP_ANNOTATE=1 leave the merged TSV with short identifiers only
#   DRY_RUN=1       propagated to the prediction stage
set -euo pipefail

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
[[ -f "$_d/lib/peps_common.sh" ]] || { echo "ERROR: lib/peps_common.sh not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_d/lib/peps_common.sh"

MODE_IN=""; KEY=""; LAUNCH="standard"; JOBS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --massive)  LAUNCH="massive"; shift ;;
    --standard) LAUNCH="standard"; shift ;;
    --jobs)     JOBS="${2:?--jobs needs a number}"; shift 2 ;;
    -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
    -*)         peps_die "unknown option: $1" ;;
    *)
      if   [[ -z "$MODE_IN" ]]; then MODE_IN="$1"
      elif [[ -z "$KEY"     ]]; then KEY="$1"
      else peps_die "unexpected argument: $1"
      fi
      shift ;;
  esac
done

[[ -n "$MODE_IN" && -n "$KEY" ]] || {
  echo "Usage: bash $(basename "$0") <MHC1|MHC2> <PROTEOME_KEY> [--massive] [--jobs N]" >&2
  exit 1
}

peps_mode_config "$MODE_IN"
peps_registry_row "$KEY" || peps_die "proteome key not in registry: $KEY"

RUN_PREDICT="$PEPS_SCRIPTS/predict/run_predict.sh"
HIVE="$PEPS_SCRIPTS/predict/hive.sh"
CLEANPARSE="$PEPS_SCRIPTS/parse/run_cleanparse.sh"
ANNOTATE="$PEPS_SCRIPTS/prep/pp_annotate.sh"
BACKUP="$PEPS_SCRIPTS/util/gs_backupbucket.sh"
CLEANDISK="$PEPS_SCRIPTS/util/gs_cleandisk.sh"
peps_require_file "$RUN_PREDICT" "$HIVE" "$CLEANPARSE" "$ANNOTATE" "$BACKUP" "$CLEANDISK"

BASE_OUT="$(peps_base_out "$PROTEOME_ORGANISM" "$KEY" "$MHC_DIR" "$PROG")"
LENGTHS=( $(peps_lengths "$MODE") )

peps_section "END2END  $MODE  $KEY  ($PROTEOME_ORGANISM)"
echo "  launcher : $LAUNCH"
echo "  lengths  : ${LENGTHS[*]}"
echo ""

# --- 1. prediction ---------------------------------------------------------
peps_section "1/5  prediction"
if [[ "$LAUNCH" == "massive" ]]; then
  bash "$HIVE" "$MODE" "$PROTEOME_ORGANISM" ${JOBS:+"$JOBS"}
else
  bash "$RUN_PREDICT" "$MODE" "$KEY"
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  peps_log "DRY_RUN: stopping after the prediction stage"
  exit 0
fi

RUNDIR="$(peps_find_rundir "$BASE_OUT")"
[[ -n "$RUNDIR" ]] || peps_die "no run directory found under $BASE_OUT"
peps_log "run directory: $RUNDIR"

# --- 2. clean and parse ----------------------------------------------------
peps_section "2/5  clean and parse"
bash "$CLEANPARSE" "$RUNDIR" "$MODE"

MERGED="$RUNDIR/cp/merged/merged_$(printf '%s' "$MODE" | tr '[:upper:]' '[:lower:]').tsv"

# --- 3. annotate -----------------------------------------------------------
peps_section "3/5  annotate"
if [[ "${SKIP_ANNOTATE:-0}" == "1" ]]; then
  peps_log "skipped (SKIP_ANNOTATE=1)"
elif [[ ! -s "$MERGED" ]]; then
  peps_warn "merged TSV not found, nothing to annotate: $MERGED"
elif [[ "$PROTEOME_INPUT_MODE" != "renamed" ]]; then
  peps_warn "input_mode is '$PROTEOME_INPUT_MODE', so there is no dictionary to join against."
  peps_warn "Identifiers in the merged TSV are whatever survived truncation."
else
  bash "$ANNOTATE" "$MERGED" "${MERGED%.tsv}_annotated.tsv"
fi

# --- 4. backup -------------------------------------------------------------
peps_section "4/5  backup"
if [[ "${SKIP_BACKUP:-0}" == "1" ]]; then
  peps_log "skipped (SKIP_BACKUP=1)"
else
  bash "$BACKUP" || peps_warn "backup reported a problem; not deleting anything"
fi

# --- 5. cleanup ------------------------------------------------------------
# Only ever runs after a backup, because it deletes the raw predictor output.
peps_section "5/5  cleanup"
if [[ "${SKIP_CLEAN:-0}" == "1" ]]; then
  peps_log "skipped (SKIP_CLEAN=1)"
elif [[ "${SKIP_BACKUP:-0}" == "1" ]]; then
  peps_warn "backup was skipped, so raw output is being kept"
else
  bash "$CLEANDISK" "$RUNDIR"
fi

peps_section "DONE  $KEY"
echo "  rundir   : $RUNDIR"
echo "  merged   : $MERGED"
[[ -s "${MERGED%.tsv}_annotated.tsv" ]] && echo "  annotated: ${MERGED%.tsv}_annotated.tsv"
