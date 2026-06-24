# peps-pipeline

**Peptidome prediction pipeline for *Leishmania* (subgenus *Viannia* and relatives)**

A reproducible, Docker-based pipeline for large-scale MHC-I and MHC-II peptide binding predictions using NetMHCpan 4.2 and NetMHC2pan 4.3. Designed to run on Google Cloud VMs, but portable to any Linux environment with Docker installed.

---

## Scientific context

This pipeline is part of a reverse vaccinology project aimed at identifying candidate T-cell epitopes across 11 *Leishmania* proteomes. It predicts peptide–MHC binding for both class I (9-mers) and class II (15-mers) molecules using a curated set of HLA alleles relevant to Latin American populations.

---

## Repository structure

```
peps-pipeline/
├── scripts/
│   ├── queue.sh              # Main orchestrator — run this to launch campaigns
│   ├── end2end.sh            # Per-proteome coordinator (called by queue.sh)
│   ├── run_NMP_MHC1.sh       # NetMHCpan 4.2 runner (MHC-I, 9-mers)
│   ├── run_NMP_MHC2.sh       # NetMHC2pan 4.3 runner (MHC-II, 15-mers)
│   ├── run_cleanparse.sh     # Parser: cleans and extracts binder TSVs
│   ├── gs_backupbucket.sh    # Backs up outputs to Google Cloud Storage
│   └── gs_cleandisk.sh       # Removes processed data from local disk
├── configs/
│   ├── proteomes.tsv         # Proteome registry (key, species, fasta path)
│   ├── alleles_mhc1.txt      # HLA class I alleles
│   └── alleles_mhc2.txt      # HLA class II alleles
├── docker/
│   ├── netmhcpan/
│   │   └── Dockerfile        # NetMHCpan 4.2 image
│   └── netmhc2pan/
│       └── Dockerfile        # NetMHC2pan 4.3 image
└── README.md
```

---

## Requirements

| Dependency | Version | Notes |
|---|---|---|
| Docker | ≥ 20.x | Required to run prediction tools |
| Bash | ≥ 4.x | All scripts use `set -euo pipefail` |
| Google Cloud SDK | any | Required only for GCS backup scripts |
| `gcloud` auth | configured | `gcloud auth application-default login` |

> **Note:** NetMHCpan and NetMHC2pan are licensed tools from DTU Health Tech. You must obtain your own academic license and build the Docker images yourself using the Dockerfiles provided. The pre-built images are **not** distributed with this repository.

---

## Proteomes

| Key | Species |
|---|---|
| Lbra | *Leishmania braziliensis* |
| Ldon | *Leishmania donovani* |
| Lguy | *Leishmania guyanensis* |
| Linf | *Leishmania infantum* |
| Llin | *Leishmania lindenbergi* |
| Lmaj | *Leishmania major* |
| Lmex | *Leishmania mexicana* |
| Lnai | *Leishmania naiffi* |
| Lpan_v1 | *Leishmania panamensis* (strain 1) |
| Lpan_v2 | *Leishmania panamensis* (strain 2) |
| Lsha | *Leishmania shawi* |

---

## HLA alleles (MHC-I)

```
HLA-A02:01  HLA-A24:02  HLA-A31:01  HLA-A68:01
HLA-B15:01  HLA-B39:01  HLA-B40:02
HLA-C03:03  HLA-C04:01  HLA-C07:02  HLA-C15:02
```

---

## Output structure

All outputs are written to `/data/out/peptidome/prediction/` with the following hierarchy:

```
/data/out/peptidome/prediction/
└── {PROTEOME}/
    ├── MHC1/
    │   └── netmhcpan_4.2/
    │       └── run_001/
    │           └── cp/
    │               ├── cleanout/   # Raw tool output
    │               └── parse/      # Parsed TSVs (binders per allele)
    └── MHC2/
        └── netmhc2pan_4.3/
            └── run_001/
                └── cp/
                    ├── cleanout/
                    └── parse/
```

---

## How to run

### 1. Build Docker images

```bash
# MHC-I
cd docker/netmhcpan/
docker build -t netmhcpan:4.2 .

# MHC-II
cd docker/netmhc2pan/
docker build -t netmhc2pan:4.3 .
```

### 2. Set up configs

Edit `configs/proteomes.tsv` to point to your local FASTA paths. The allele files are ready to use as-is.

### 3. Launch a campaign

Always use `tmux` or `screen` before running — campaigns can take many hours and must survive SSH disconnection.

```bash
# Start a persistent session
tmux new-session -s campaign

# Edit queue.sh to select which proteomes and modes to run,
# then launch:
nohup bash ~/scripts/queue.sh >> ~/queue.log 2>&1 &

# Monitor progress
tail -f ~/queue.log

# Detach from tmux: Ctrl+B, D
# Reattach later: tmux attach -t campaign
```

### 4. Run a single proteome

```bash
nohup bash ~/scripts/end2end.sh MHC1 Lbra >> ~/lbra_mhc1.log 2>&1 &
```

### 5. Resume an interrupted campaign

The `end2end.sh` script detects existing `run_*` directories and creates a new numbered run. No data is overwritten.

---

## Pipeline flow

```
queue.sh
└── end2end.sh <MODE> <PROTEOME>
        ├── run_NMP_MHC1.sh  OR  run_NMP_MHC2.sh
        │       └── Docker (netmhcpan:4.2 / netmhc2pan:4.3)
        ├── run_cleanparse.sh   → TSVs in parse/
        ├── gs_backupbucket.sh  → GCS backup
        └── gs_cleandisk.sh     → local cleanup
```

---

## Reproducibility

- All scripts are version-controlled in this repository.
- Docker images are built from pinned Dockerfiles with explicit tool versions.
- Each campaign should be tagged with the current Git commit:
  ```bash
  git rev-parse --short HEAD
  ```
- Raw outputs are archived to Google Cloud Storage before local deletion.
- Parsed TSVs are the primary analysis-ready deliverable.

---

## License

Scripts and Dockerfiles in this repository are released under the MIT License.

**NetMHCpan and NetMHC2pan are not included.** These tools require a separate academic license from DTU Health Tech:
- NetMHCpan: https://services.healthtech.dtu.dk/services/NetMHCpan-4.2/
- NetMHC2pan: https://services.healthtech.dtu.dk/services/NetMHCIIpan-4.3/

---

## Citation

If you use this pipeline, please cite the underlying tools:

- Reynisson et al. (2020). NetMHCpan-4.1 and NetMHCIIpan-4.0. *Nucleic Acids Research*.
- [Your thesis / preprint citation here]

---

## Contact

A. Cristina Ortega — Universidad Tecnologica de Panama  
GitHub: @pepperandhoney 
email: ana.ortega6@utp.ac.pa