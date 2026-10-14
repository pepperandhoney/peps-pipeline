# peps-pipeline v3

**Peptidome prediction pipeline for MHC-I and MHC-II epitope discovery**

A reproducible, Docker-based pipeline for large-scale peptide–MHC binding
prediction with NetMHCpan 4.2 and NetMHCIIpan 4.3. Built for *Leishmania* and
generalised to any organism.

---

## What v3 adds

v2 solved the problem that made the pipeline necessary — protein identity was
being destroyed by the predictors — but the solution was never wired into the
flow, and the pipeline could only run one peptide length at a time. v3 finishes
the job and harmonises the parts.

| | v2 | v3 |
|---|---|---|
| Protein identity | `pp_annotate.sh` existed but nothing called it | `end2end.sh` runs it; merged tables arrive annotated |
| Peptide lengths | one hard-coded length in three separate files | one list in `configs/lengths.conf`, read everywhere |
| Massive campaigns | a separate `bee`/`hive` pair that had drifted out of sync | `hive.sh` as a first-class mode, sharing the registry, layout and execution unit |
| Shared conventions | each script resolved paths its own way | `lib/peps_common.sh`, sourced by all |
| Class I EL columns | only the 4.0 spelling was recognised | both spellings; a silent all-NA column is impossible |
| Allele names | colons stripped, breaking joins against IEDB | `MHC` verbatim, `MHC_key` punctuation-free |
| QC | `expected_peptides: SKIPPED` | expected counts computed; an incomplete run exits non-zero |
| Tests | 33 checks | 57 checks, including both failure modes |

### The problem the pipeline exists for

NetMHCpan and NetMHCIIpan truncate the FASTA identifier to 15 characters and
replace dots with underscores:

```
>LbrM.01.2.000040   ─┐
>LbrM.01.2.000041    ├──►  LbrM_01_2_00004
>LbrM.01.2.000042   ─┘
```

Three proteins, one identifier. Every peptide from them is attributed to the
same place and the protein of origin is gone. TriTrypDB accessions such as
`LAEL147_000872300.1-p1` are 22 characters and lose even more.

`pp_renumber.sh` assigns each protein a fixed-width identifier that fits, and
keeps a dictionary:

```
LAETP000001    4-character prefix + P + 6 digits = 11 characters
```

Eleven characters leave four to spare, six digits cover 999,999 proteins per
proteome, and nothing is discarded — `pp_annotate.sh` restores the original
accession and description after parsing.

---

## Layout

```
peps-pipeline/
├── lib/
│   └── peps_common.sh              paths, registry, logging, run directories
├── scripts/
│   ├── queue.sh                    run a campaign
│   ├── end2end.sh                  one proteome: predict → parse → annotate → archive
│   ├── prep/
│   │   ├── pp_prepare.sh           clean + renumber (start here)
│   │   ├── pp_renumber.sh          assign identifiers, write the dictionary
│   │   └── pp_annotate.sh          restore accessions and descriptions
│   ├── predict/
│   │   ├── run_predict.sh          standard mode: one proteome
│   │   ├── bee.sh                  one job: proteome × allele × length
│   │   ├── hive.sh                 massive mode: many jobs, GNU Parallel
│   │   ├── run_NMP_MHC1.sh         wrapper, the v2 name
│   │   └── run_NMP_MHC2.sh         wrapper, the v2 name
│   ├── parse/
│   │   ├── run_cleanparse.sh       clean → parse → merge → QC
│   │   ├── cp_cleanout.awk         strip predictor noise
│   │   ├── cp_parse_NMP_MHC1_4.2.awk
│   │   ├── cp_parse_NMP_MHC2_4.3.awk
│   │   ├── cp_mergetsv.sh
│   │   └── cp_qc.sh                completeness report
│   └── util/
│       ├── gs_backupbucket.sh      back up to Google Cloud Storage
│       └── gs_cleandisk.sh         remove intermediates after backup
├── configs/
│   ├── proteomes.tsv               key, organism, input_mode, fasta_file, prefix
│   ├── proteome_sources.tsv        strain, taxid, UniProt proteome
│   ├── lengths.conf                peptide lengths per class
│   ├── alleles_mhc1.txt
│   └── alleles_mhc2.txt
├── docker/
├── tests/
│   ├── run_tests.sh                57 checks, no Docker
│   └── fake_netmhc.py              predictor stand-in
├── README.md
└── CHANGELOG.md
```

---

## Requirements

| Dependency | Version | Notes |
|---|---|---|
| Docker | ≥ 20.x | for the prediction tools |
| Bash | ≥ 4.x | `set -euo pipefail` throughout |
| GNU Parallel | any | massive mode only |
| seqkit | any | optional; `pp_prepare.sh` falls back to awk |
| Google Cloud SDK | any | the backup script only |

NetMHCpan and NetMHCIIpan are licensed by DTU Health Tech and are **not**
distributed here. Obtain an academic licence and build the images from the
Dockerfiles provided.

---

## Usage

### 1. Build the images

```bash
cd docker/netmhcpan/  && docker build -t netmhcpan:4.2 .
cd docker/netmhc2pan/ && docker build -t netmhc2pan:4.3 .
```

### 2. Prepare each proteome

Once per proteome. The prefix is four uppercase alphanumeric characters and
becomes the registry key.

```bash
bash scripts/prep/pp_prepare.sh LAET /data/in/proteomes/TriTrypDB-67_LaethiopicaL147.fasta
```

Writes:

```
/data/in/proteomes/clean/LAET.clean.faa       cleaned, original headers
/data/in/proteomes/renamed/LAET.faa           renumbered, ready to predict
/data/in/proteomes/renamed/LAET.iddict.tsv    dictionary for this proteome
/data/in/proteomes/renamed/iddict_global.tsv  every dictionary
```

Cleaning drops sequences shorter than `MINLEN` and any sequence containing a
non-standard residue. The counts are printed; if a benchmark expects specific
peptides, check they do not come from a dropped protein.

### 3. Register it

Add a row to `configs/proteomes.tsv`. **Key and prefix must be identical** —
letting them drift is what produced three labels for one proteome in v1.

```
key     organism    input_mode  fasta_file  prefix
LAET    leishmania  renamed     LAET.faa    LAET
```

### 4. Choose the peptide lengths

`configs/lengths.conf` describes the campaign in one place:

```bash
MHC1_LENGTHS="9"
MHC2_LENGTHS="15"
```

Override for a single run without editing the file:

```bash
PEPS_LENGTHS_MHC1="8 9 10 11 12 13 14" bash scripts/end2end.sh MHC1 LAET
```

### 5. Run

Always inside tmux or screen — a campaign outlives an SSH session.

```bash
tmux new-session -s campaign

bash scripts/end2end.sh MHC1 LAET                    # one proteome
nohup bash scripts/queue.sh leishmania >> ~/q.log &  # one organism
nohup bash scripts/queue.sh --massive --jobs 20 >> ~/q.log &
```

Re-running the same command retries only what is missing: every job skips work
that already completed.

---

## Standard mode and massive mode

Both write the same `run_NNN` layout and the same `.out` files, and both use
`bee.sh` as the execution unit. The parser cannot tell them apart.

**Standard** (`run_predict.sh`) takes one proteome and works through its
allele × length grid with a bounded number of concurrent containers. The right
shape for a few proteomes at one length.

**Massive** (`hive.sh`) flattens every proteome × allele × length into one job
list and hands it to GNU Parallel. Use it when the campaign is large enough
that keeping every core busy matters, or when several lengths are in play —
the standard loop finishes one length before starting the next.

```bash
bash scripts/predict/hive.sh MHC1 leishmania 20
DRY_RUN=1 bash scripts/predict/hive.sh MHC1 leishmania   # inspect the job list
```

A single combination can be retried on its own:

```bash
bash scripts/predict/bee.sh MHC1 LAET HLA-A03:01 9 /data/out/.../run_001
```

---

## Output

```
/data/out/{ORGANISM}/prediction/{KEY}/{MHC1|MHC2}/{PROG}/run_NNN/
├── raw/        predictor output
├── err/        predictor stderr
├── alleles/    the allele list used
├── meta/       run metadata, including the commit
├── logs/
└── cp/
    ├── cleanout/
    ├── parse/      one TSV per allele × length
    ├── merged/     merged_mhc1.tsv and merged_mhc1_annotated.tsv
    └── meta/       QC report
```

Runs are numbered and never overwritten.

### Merged table columns

```
dataset  Pos  MHC  MHC_key  Peptide  Pep_Len  Core  Of  Identity
Score_EL  %Rank_EL  Score_BA  %Rank_BA  Aff(nM)  Exp_Bind  BindLevel
```

Both classes use this schema, so the two tables stack.

- `MHC` is verbatim (`HLA-A02:01`) — use it to join against IEDB, AFND and
  published allele tables, which all carry the colon.
- `MHC_key` is punctuation-free (`HLA-A0201`) — filenames, and continuity with
  v1 and v2 output.
- `Identity` is the short identifier; `_annotated.tsv` adds `original_id` and
  `description`.
- `Pep_Len` separates lengths inside a multilength run.

---

## QC

`cp_qc.sh` computes what the run should have produced and compares:

```
expected windows at length L = Σ over proteins of max(0, len_i − L + 1)
expected rows                = Σ over L of (windows_L × n_alleles)
```

It exits non-zero when completeness falls below `QC_TOLERANCE` (95% by
default), when files are missing, or when `%Rank_EL` is NA throughout — which
means the parser did not recognise the predictor's header spelling. A small
shortfall is normal: predictors skip windows containing non-standard residues.

---

## Tests

```bash
bash tests/run_tests.sh
```

Fifty-seven checks covering the library, the registry, renumbering, the
truncation collision and its fix, both parsers in both header spellings,
merging, QC on a passing and a failing run, the annotation round trip, and the
massive-mode job list. Docker is not required; a Python stand-in reproduces the
predictor's output format, including the truncation.

---

## Environment

Every path can be overridden, so the pipeline runs on a laptop, a VM or in CI
without editing a script.

| Variable | Default |
|---|---|
| `PEPS_DATA_IN` | `/data/in/proteomes` |
| `PEPS_DATA_OUT` | `/data/out` |
| `PEPS_CONFIG` | `<repo>/configs` |
| `PEPS_LENGTHS_MHC1` / `_MHC2` | from `configs/lengths.conf` |
| `PEPS_IMAGE_MHC1` / `_MHC2` | `netmhcpan:4.2` / `netmhc2pan:4.3` |
| `MAX_PARALLEL` | 6 |
| `QC_TOLERANCE` | 95 |
| `DRY_RUN`, `FORCE`, `SKIP_BACKUP`, `SKIP_CLEAN`, `SKIP_ANNOTATE` | off |

---

## Migrating from v2

Predictions made with v2 remain valid; v3 changes how they are launched and
parsed, not what the predictors do.

1. Scripts moved into `prep/`, `predict/`, `parse/` and `util/`. The two v2
   runner names still work as wrappers.
2. `run_cleanparse.sh` no longer takes a length argument — it reads the lengths
   from the run metadata, because a multilength run has no single length.
3. Parsed tables gained `MHC_key` and `Pep_Len`, and `MHC` now keeps its colon.
   Anything that joined on the colon-free form should use `MHC_key`.
4. `configs/lengths.conf` is new. Without it the defaults are 9 and 15, which
   is what v2 did.

Re-parsing a v2 run under v3 is cheap and gives the new columns:

```bash
bash scripts/parse/run_cleanparse.sh /data/out/.../run_001 MHC1
```

---

## Reproducibility

- Docker images are built from pinned Dockerfiles with explicit tool versions.
- Every run writes `meta/run.meta.txt` with image, tool, input FASTA, alleles,
  lengths and — when the repository is a git checkout — the commit.
- `configs/proteome_sources.tsv` records strain, taxonomy ID and UniProt
  proteome for every registered proteome.
- Raw output is archived to Google Cloud Storage before local deletion, and
  `gs_cleandisk.sh` never runs when the backup was skipped.

---

## Licence

Scripts and Dockerfiles are released under the MIT Licence.

NetMHCpan and NetMHCIIpan require a separate academic licence from DTU Health Tech:

- NetMHCpan: https://services.healthtech.dtu.dk/services/NetMHCpan-4.2/
- NetMHCIIpan: https://services.healthtech.dtu.dk/services/NetMHCIIpan-4.3/

---

## Citation

- Reynisson B, Alvarez B, Paul S, Peters B, Nielsen M (2020). NetMHCpan-4.1 and
  NetMHCIIpan-4.0. *Nucleic Acids Research* 48:W449–W454.
- Ortega-Batista AC (2026). peps-pipeline: a reproducible peptidome prediction
  pipeline. Zenodo. https://doi.org/10.5281/zenodo.20837440

---

## Contact

Ana Cristina Ortega — Universidad Tecnológica de Panamá
GitHub: @pepperandhoney · ana.ortega6@utp.ac.pa
