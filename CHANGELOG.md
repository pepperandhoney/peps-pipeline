# Changelog

## v3.0.0

### Fixed

- **The fix for truncated identifiers was never applied.** v2 added
  `pp_annotate.sh` but `end2end.sh` did not call it, so every merged table kept
  the short identifiers and the accession had to be restored by hand. The
  pipeline looked as though it still lost the protein of origin. Annotation is
  now a stage of `end2end.sh`.

- **Class I eluted-ligand columns were parsed as NA.** The parser looked only
  for `Score` and `%Rank`, the NetMHCpan 4.0 spelling. Run with `-BA`, versions
  4.1 and 4.2 emit `Score_EL` and `%Rank_EL`, so every EL value became NA —
  silently, because NA is also what an absent column produces. Both spellings
  are now accepted, and `run_cleanparse.sh` and `cp_qc.sh` fail loudly when the
  column is NA throughout.

- **Allele names lost their colon.** The parsers ran `gsub(/:/, "", MHC)`,
  turning `HLA-A02:01` into `HLA-A0201` and breaking joins against IEDB, AFND
  and published allele tables. `MHC` is now verbatim; the punctuation-free form
  moved to a new `MHC_key` column.

- **A `bee.sh` length list was missing 15.** The out-of-tree multilength runner
  used `(11 12 13 14 16 17 18 19 20 21)` — ten values, so the count looked
  right, but 11 is outside the class II range and 15-mers were never predicted.
  Lengths now come from one configuration file.

- **QC could not detect an incomplete run.** `cp_qc.sh` printed
  `expected_peptides: SKIPPED`; it counted rows but compared them to nothing, so
  a run that produced half its output was indistinguishable from a complete one.

### Added

- `lib/peps_common.sh` — path resolution, the proteome registry, logging,
  validation and run-directory management, sourced by every script. Each script
  previously resolved `SCRIPTS_DIR` its own way and three of them disagreed.
- `scripts/predict/hive.sh` and `bee.sh` — massive mode, a first-class
  alternative to standard mode for campaigns spanning many proteomes, alleles
  and lengths. Both modes use `bee.sh` as the execution unit and write the same
  layout, so the parser cannot tell them apart.
- `configs/lengths.conf` — peptide lengths per class, in one place.
- `Pep_Len` and `MHC_key` columns in both parsers.
- `tests/fake_netmhc.py` — a predictor stand-in that reproduces the
  15-character truncation and the dot-to-underscore replacement, so the
  behaviour the pipeline exists to work around is covered by a test.
- `DRY_RUN` throughout the prediction stage.

### Changed

- Scripts are grouped into `prep/`, `predict/`, `parse/` and `util/`.
- One runner, `run_predict.sh`, replaces the two near-identical v2 runners; the
  per-tool flags live in `peps_mode_config()`. The v2 names remain as wrappers.
- `run_cleanparse.sh` no longer takes a length argument; a multilength run has
  no single length, so it reads them from the run metadata.
- `cp_qc.sh` computes expected window and row counts from the input FASTA and
  exits non-zero below `QC_TOLERANCE` (95% by default).
- `gs_cleandisk.sh` is skipped automatically when the backup was skipped, so
  raw output is never deleted without a copy.
- The test suite grew from 33 checks to 57, including an incomplete run and the
  old header spelling.

### Unchanged

`cp_cleanout.awk`, `cp_mergetsv.sh`, `gs_backupbucket.sh` and `gs_cleandisk.sh`
are carried over from v2. The identifier scheme is unchanged, so v2 dictionaries
remain valid.

---

## v2.0.0

### Fixed

- **Protein identity was lost after prediction.** NetMHCpan truncates FASTA
  headers to 15 characters, so accessions could not be recovered reliably.
  Gene-style identifiers such as `LbrM.01.2.000040` (16 characters) lost their
  final digit, making distinct proteins indistinguishable. Proteomes are now
  renumbered before prediction with fixed-width identifiers, and a dictionary
  preserves the original accession and description.

- **Proteome key matching in `end2end.sh` never worked.** The check used
  `grep -q "^${KEY}\t"`, but bash does not expand `\t` inside double quotes, so
  grep searched for a literal `t`. Replaced with `awk -F'\t'` exact field
  comparison.

- **Dataset labels drifted between runs.** The same proteome appeared as
  `Lpanv2_mhc1`, `Lpan_v1` and `Lpanv1` because the registry column was edited
  by hand. The key and the prefix are now the same string and the test suite
  enforces it.

### Added

- `pp_renumber.sh`, `pp_prepare.sh`, `pp_annotate.sh`
- `configs/proteome_sources.tsv`
- `tests/run_tests.sh` — 33 checks that run without Docker
- Organism filter in `queue.sh`

### Changed

- Output paths include the organism: `/data/out/{ORGANISM}/prediction/...`
- `proteomes.tsv` has five columns (added `organism`)
- Registered proteomes cover *Leishmania* (10), influenza A and B,
  *M. tuberculosis* and *P. falciparum*
