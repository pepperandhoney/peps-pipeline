#!/usr/bin/env bash
# queue.sh — Main orchestrator
# Usage: nohup bash ~/scripts/queue.sh >> ~/queue.log 2>&1 &
# Runs MHC-I (NetMHCpan 4.2) and MHC-II (NetMHC2pan 4.3)
# predictions for all 11 Leishmania proteomes.
set -euo pipefail
export LC_ALL=C
LOG="$HOME/queue.log"
exec > >(tee -a "$LOG") 2>&1
echo "==================== QUEUE START ===================="
date
# ---------- MHC1 ----------
bash "$HOME/scripts/end2end.sh" MHC1 Lbra
bash "$HOME/scripts/end2end.sh" MHC1 Ldon
bash "$HOME/scripts/end2end.sh" MHC1 Lguy
bash "$HOME/scripts/end2end.sh" MHC1 Linf
bash "$HOME/scripts/end2end.sh" MHC1 Llin
bash "$HOME/scripts/end2end.sh" MHC1 Lmaj
bash "$HOME/scripts/end2end.sh" MHC1 Lmex
bash "$HOME/scripts/end2end.sh" MHC1 Lnai
bash "$HOME/scripts/end2end.sh" MHC1 Lpan_v1
bash "$HOME/scripts/end2end.sh" MHC1 Lpan_v2
bash "$HOME/scripts/end2end.sh" MHC1 Lsha
# ---------- MHC2 ----------
bash "$HOME/scripts/end2end.sh" MHC2 Lbra
bash "$HOME/scripts/end2end.sh" MHC2 Ldon
bash "$HOME/scripts/end2end.sh" MHC2 Lguy
bash "$HOME/scripts/end2end.sh" MHC2 Linf
bash "$HOME/scripts/end2end.sh" MHC2 Llin
bash "$HOME/scripts/end2end.sh" MHC2 Lmaj
bash "$HOME/scripts/end2end.sh" MHC2 Lmex
bash "$HOME/scripts/end2end.sh" MHC2 Lnai
bash "$HOME/scripts/end2end.sh" MHC2 Lpan_v1
bash "$HOME/scripts/end2end.sh" MHC2 Lpan_v2
bash "$HOME/scripts/end2end.sh" MHC2 Lsha
echo "==================== QUEUE DONE ====================="
date
