#!/usr/bin/env bash
# queue.sh — run a whole campaign
#
# USAGE
#   bash queue.sh [ORGANISM] [--massive] [--jobs N] [--mode MHC1|MHC2]
#
#   bash queue.sh                          # every proteome, both classes
#   bash queue.sh leishmania               # one organism
#   bash queue.sh leishmania --mode MHC1   # one organism, class I only
#   bash queue.sh --massive --jobs 20      # massive mode throughout
#
# Always start this inside tmux or screen: a campaign runs for hours or days
# and must survive an SSH disconnection.
#
#   tmux new-session -s campaign
#   nohup bash scripts/queue.sh leishmania >> ~/queue.log 2>&1 &
#   tail -f ~/queue.log
#
# A failing proteome does not stop the campaign; the failure is recorded and
# reported in the summary. Re-running the same command retries only what is
# missing, because every bee skips work that is already complete.
set -uo pipefail   # deliberately not -e: one failure must not end the queue

_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_d" != "/" && ! -f "$_d/lib/peps_common.sh" ]]; do _d="$(dirname "$_d")"; done
[[ -f "$_d/lib/peps_common.sh" ]] || { echo "ERROR: lib/peps_common.sh not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$_d/lib/peps_common.sh"

ORGANISM=""; EXTRA=(); MODES=(MHC1 MHC2)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --massive|--standard) EXTRA+=("$1"); shift ;;
    --jobs)               EXTRA+=(--jobs "${2:?--jobs needs a number}"); shift 2 ;;
    --mode)               MODES=( "$(printf '%s' "${2:?--mode needs MHC1 or MHC2}" | tr '[:lower:]' '[:upper:]')" ); shift 2 ;;
    -h|--help)            sed -n '2,25p' "$0"; exit 0 ;;
    -*)                   peps_die "unknown option: $1" ;;
    *)                    ORGANISM="$1"; shift ;;
  esac
done

END2END="$PEPS_SCRIPTS/end2end.sh"
peps_require_file "$END2END"

mapfile -t KEYS < <(peps_registry_keys "$ORGANISM")
if [[ "${#KEYS[@]}" -eq 0 ]]; then
  peps_warn "no proteomes matched${ORGANISM:+ for organism '$ORGANISM'}"
  echo "Registered organisms:"
  peps_registry_organisms | sed 's/^/  /'
  exit 1
fi

peps_section "QUEUE START"
echo "  organism : ${ORGANISM:-(all)}"
echo "  proteomes: ${#KEYS[@]}"
printf '    %s\n' "${KEYS[@]}"
echo "  classes  : ${MODES[*]}"
echo "  options  : ${EXTRA[*]:-(none)}"
for M in "${MODES[@]}"; do
  echo "  lengths $M: $(peps_lengths "$M")"
done
echo ""

OK=0; FAIL=0; FAILED_LIST=()

for MODE in "${MODES[@]}"; do
  for KEY in "${KEYS[@]}"; do
    peps_section "$MODE  $KEY"
    if bash "$END2END" "$MODE" "$KEY" "${EXTRA[@]}"; then
      OK=$((OK + 1))
    else
      peps_warn "FAILED: $MODE $KEY"
      FAIL=$((FAIL + 1))
      FAILED_LIST+=("$MODE $KEY")
    fi
  done
done

peps_section "QUEUE DONE"
echo "  succeeded: $OK"
echo "  failed:    $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo "  Retry these:"
  printf '    bash scripts/end2end.sh %s\n' "${FAILED_LIST[@]}"
fi
exit $(( FAIL > 0 ? 1 : 0 ))
