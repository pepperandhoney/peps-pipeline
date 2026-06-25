# Tests

Quick validation suite for the peps-pipeline.

## What it tests

Runs a full end-to-end prediction on 3 *Leishmania major* proteins with:
- MHC-I: 1 allele (HLA-A02:01) via NetMHCpan 4.2
- MHC-II: 1 allele (DRB1_0411) via NetMHC2pan 4.3

Covers the full pipeline: prediction → parsing → merge → QC → backup → cleanup.

## Requirements

- Docker images `netmhcpan:4.2` and `netmhc2pan:4.3` must be built and available
- GCS credentials configured (`gcloud auth application-default login`)
- `/data/` directory mounted and writable

## Usage

From the root of the repository:

```bash
bash tests/run_test.sh
```

Expected runtime: ~2 minutes.
Expected output: `All tests passed.`

## Test files

| File | Description |
|---|---|
| `test_mini.faa` | 3 proteins from *L. major* proteome |
| `test_proteomes.tsv` | Proteome registry entry for Ltest |
| `test_alleles_mhc1.txt` | Single MHC-I allele (HLA-A02:01) |
| `test_alleles_mhc2.txt` | Single MHC-II allele (DRB1_0411) |
| `run_test.sh` | Test runner script |
