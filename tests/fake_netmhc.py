#!/usr/bin/env python3
"""
fake_netmhc.py — emit output shaped like NetMHCpan / NetMHCIIpan

Lets the parsing, merging, QC and annotation stages be tested without the
licensed Docker images. It reproduces the two behaviours of the real tools
that the pipeline has to work around:

  · the Identity field is truncated to 15 characters
  · dots in the identifier become underscores

Pass --truncate to reproduce them, which is what a run on non-renumbered
headers looks like. Without the flag the identifier is emitted whole, which is
what a run on pp_renumber.sh output looks like.

Usage:
  python3 fake_netmhc.py --fasta in.faa --allele HLA-A02:01 --length 9 --mode MHC1
  python3 fake_netmhc.py --fasta in.faa --allele DRB1_0701 --length 15 --mode MHC2 --truncate
"""

import argparse
import hashlib
import sys

TRUNC = 15


def leer_fasta(ruta):
    ident, partes = None, []
    with open(ruta) as fh:
        for linea in fh:
            linea = linea.rstrip("\n\r")
            if not linea:
                continue
            if linea.startswith(">"):
                if ident is not None:
                    yield ident, "".join(partes)
                ident = linea[1:].split()[0]
                partes = []
            else:
                partes.append(linea.strip().upper())
    if ident is not None:
        yield ident, "".join(partes)


def pseudoscore(pep, allele):
    """Deterministic pseudo-random score so tests are reproducible."""
    h = hashlib.md5(f"{pep}|{allele}".encode()).hexdigest()
    return int(h[:8], 16) / 0xFFFFFFFF


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--fasta", required=True)
    p.add_argument("--allele", required=True)
    p.add_argument("--length", type=int, required=True)
    p.add_argument("--mode", choices=["MHC1", "MHC2"], default="MHC1")
    p.add_argument("--truncate", action="store_true",
                   help="mimic the 15-character truncation and dot replacement")
    a = p.parse_args()

    L = a.length
    out = sys.stdout

    if a.mode == "MHC1":
        out.write("# NetMHCpan version 4.2\n")
    else:
        out.write("# NetMHCIIpan version 4.3\n")
    out.write("\n# Tmpdir made /tmp/fake\n")
    out.write("# Input is in FASTA format\n\n")
    out.write(f"{a.allele} : Distance to training data  0.000\n\n")
    out.write("# Rank Threshold for Strong binding peptides   0.500\n")
    out.write("# Rank Threshold for Weak binding peptides   2.000\n")
    out.write("-" * 110 + "\n")

    if a.mode == "MHC1":
        hdr = (" Pos          MHC        Peptide       Core Of Gp Gl Ip Il"
               "        Identity  Score_EL %Rank_EL  Score_BA %Rank_BA  Aff(nM) BindLevel")
    else:
        hdr = (" Pos          MHC        Peptide       Core Of"
               "        Identity  Score_EL %Rank_EL Exp_Bind  Score_BA %Rank_BA  Aff(nM) BindLevel")
    out.write(hdr + "\n")
    out.write("-" * 110 + "\n")

    n = 0
    for ident, seq in leer_fasta(a.fasta):
        shown = ident
        if a.truncate:
            shown = shown.replace(".", "_")[:TRUNC]
        for i in range(len(seq) - L + 1):
            pep = seq[i:i + L]
            if not set(pep) <= set("ACDEFGHIKLMNPQRSTVWY"):
                continue
            s = pseudoscore(pep, a.allele)
            rank_el = round(s * 100, 4)
            score_el = round(1 - s, 6)
            rank_ba = round((1 - s) * 100, 4)
            score_ba = round(s, 6)
            aff = round(50000 * s, 2)
            core = pep[:9]
            lvl = ""
            if rank_el <= 0.5:
                lvl = " <= SB"
            elif rank_el <= 2.0:
                lvl = " <= WB"

            if a.mode == "MHC1":
                out.write(f"{i+1:>4} {a.allele:>14} {pep:>14} {core:>10}  0  0  0  0  0 "
                          f"{shown:>15} {score_el:>9} {rank_el:>8} "
                          f"{score_ba:>9} {rank_ba:>8} {aff:>8}{lvl}\n")
            else:
                out.write(f"{i+1:>4} {a.allele:>14} {pep:>22} {core:>10}  0 "
                          f"{shown:>15} {score_el:>9} {rank_el:>8} {0:>8} "
                          f"{score_ba:>9} {rank_ba:>8} {aff:>8}{lvl}\n")
            n += 1

    out.write("-" * 110 + "\n")
    out.write(f"\n# Total number of peptides: {n}\n")


if __name__ == "__main__":
    main()
