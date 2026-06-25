#!/usr/bin/env bash
# run_test.sh — Quick pipeline validation test
# Usage: bash tests/run_test.sh
# Runs MHC-I and MHC-II predictions on 3 proteins with 1 allele each.
# Expected runtime: ~2 minutes.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(dirname "$TESTS_DIR")/scripts"
PROTEOMES_TSV="$SCRIPTS_DIR/proteomes.tsv"

cleanup() {
    sed -i '/^Ltest/d' "$PROTEOMES_TSV" 2>/dev/null || true
    rm -f /data/in/proteomes/clean/test_mini.faa
    rm -rf /data/out/peptidome/prediction/Ltest
}
trap cleanup EXIT

# Setup
cp "$TESTS_DIR/test_mini.faa" /data/in/proteomes/clean/test_mini.faa
echo "Ltest	clean	test_mini.faa	Ltest" >> "$PROTEOMES_TSV"
mkdir -p /data/in/proteomes/clean

# Run MHC-I test
echo "--- Running MHC-I test ---"
ALLELES_FILE_IN="$TESTS_DIR/test_alleles_mhc1.txt" \
bash "$SCRIPTS_DIR/end2end.sh" MHC1 Ltest

# Run MHC-II test
echo "--- Running MHC-II test ---"
ALLELES_FILE_IN="$TESTS_DIR/test_alleles_mhc2.txt" \
bash "$SCRIPTS_DIR/end2end.sh" MHC2 Ltest

echo "All tests passed."
