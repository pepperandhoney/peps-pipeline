#!/usr/bin/env bash
# run_NMP_MHC2.sh — compatibility wrapper (peps-pipeline v2 name)
#
# v3 has a single runner, run_predict.sh, because the two v2 runners differed
# only in the flags handed to the container and those now live in
# peps_mode_config(). This wrapper keeps the old name working so existing
# commands, notes and cron entries do not have to change.
#
#   bash run_NMP_MHC2.sh <PROTEOME_KEY>
#
# is exactly
#
#   bash run_predict.sh MHC2 <PROTEOME_KEY>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$HERE/run_predict.sh" MHC2 "$@"
