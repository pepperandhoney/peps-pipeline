# NetMHCpan Docker Installation Guide

**Author:** Ana Cristina Ortega-Batista  
**Last updated:** 2026  
**Applies to:** NetMHCpan 4.2 (MHC-I) and NetMHC2pan 4.3 (MHC-II)

---

## Overview

This guide documents how to install NetMHCpan inside an interactive Docker container and freeze it as a reusable image. This is the approach used to build the Docker images referenced in the `peps-pipeline` repository.

> **Note:** NetMHCpan and NetMHC2pan are licensed tools from DTU Health Tech. You must register with your institutional email to obtain a personalized download link. The software cannot be redistributed.
>
> - NetMHCpan 4.2: https://services.healthtech.dtu.dk/services/NetMHCpan-4.2/
> - NetMHC2pan 4.3: https://services.healthtech.dtu.dk/services/NetMHCIIpan-4.3/

---

## Prerequisites

- Docker installed and running
- An institutional email to register with DTU Health Tech
- A Linux x86_64 environment (VM or HPC)

---

## Step 1 — Open an interactive Docker container

Start a fresh Ubuntu container interactively. For NetMHCpan 4.2 use Ubuntu 24.04; for NetMHC2pan 4.3 use Ubuntu 22.04.

```bash
# NetMHCpan 4.2
docker run -it --name netmhcpan42-dev ubuntu:24.04 bash

# NetMHC2pan 4.3
docker run -it --name netmhc2pan43-dev ubuntu:22.04 bash
```

This starts a container with an interactive terminal. All subsequent steps run **inside the container**.

---

## Step 2 — Install dependencies

```bash
apt-get update
apt-get install -y \
  ca-certificates \
  wget \
  tar \
  gzip \
  perl \
  tcsh \
  gawk \
  tree \
  nano \
  less \
  xz-utils \
  ncompress \
  man-db \
  groff \
  bsdmainutils
update-ca-certificates
```

> `tcsh` is required — NetMHCpan's wrapper script is written in C shell.

---

## Step 3 — Download NetMHCpan from DTU

1. Go to https://services.healthtech.dtu.dk/
2. Select the tool you want to install (NetMHCpan 4.2 or NetMHC2pan 4.3)
3. Navigate to **Downloads** and choose the **Linux** version
4. Fill out the registration form with your institutional email
5. You will receive a **personalized download link** by email — copy it

Then inside the container:

```bash
cd /work

# Replace "YOUR_PERSONAL_LINK" with the URL from your email
wget --no-check-certificate -O netmhcpan.tar.gz "YOUR_PERSONAL_LINK"
tar -xvzf netmhcpan.tar.gz
rm netmhcpan.tar.gz
```

> For NetMHCpan 4.x you do **not** need to download a separate data folder — it is included in the tarball.

---

## Step 4 — Configure the wrapper script

NetMHCpan's main script contains hardcoded paths that must be updated to match your installation directory. Open it with a text editor:

```bash
# For NetMHCpan 4.2
nano /work/netMHCpan-4.2/netMHCpan
```

Find and update these environment variable lines:

```csh
setenv NMHOME    /work/netMHCpan-4.2
setenv NETMHCpan $NMHOME/Linux_x86_64
setenv TMPDIR    /work/netMHCpan-4.2/tmp
```

Then make the script executable:

```bash
chmod +x /work/netMHCpan-4.2/netMHCpan
mkdir -p /work/netMHCpan-4.2/tmp
```

---

## Step 5 — Run the DTU test suite

DTU provides test cases to verify the installation is correct. Run them and compare against the expected outputs:

```bash
cd /work/netMHCpan-4.2/test

# Test 1: Peptide list
csh ../netMHCpan -p test.pep > test.pep.myout
diff -I '^#' -I '^Tmpdir made' -u test.pep.out test.pep.myout && echo "pep OK"

# Test 2: FASTA input
csh ../netMHCpan test.fsa > test.fsa.myout
diff -I '^#' -I '^Tmpdir made' -u test.fsa.out test.fsa.myout && echo "fsa OK"

# Test 3: Peptide + custom HLA sequence
csh ../netMHCpan -p test.pep -hlaseq B0702.fsa test.fsa > test.pep_userMHC.myout
diff -I '^#' -I '^Tmpdir made' -u test.pep_userMHC.out test.pep_userMHC.myout && echo "hlaseq OK"

# Test 4: Binding Affinity mode (4.x only)
csh ../netMHCpan -p test.pep -BA > test.pep_BA.myout
diff -I '^#' -I '^Tmpdir made' -u test.pep_BA.out test.pep_BA.myout && echo "BA OK"
```

All four tests should print `OK`. Minor rounding differences are acceptable — the `diff` flags above ignore comment lines and temporary directory names.

---

## Step 6 — Exit and freeze the image

Once everything is installed and tested, exit the container:

```bash
exit
```

Then commit the container state as a reusable Docker image:

```bash
# For NetMHCpan 4.2
docker commit netmhcpan42-dev netmhcpan:4.2

# For NetMHC2pan 4.3
docker commit netmhc2pan43-dev netmhc2pan:4.3
```

Verify the images exist:

```bash
docker images | grep netmhc
```

---

## Step 7 — Back up the images (recommended)

Since the images cannot be rebuilt without the original download link (which expires), back them up to cloud storage:

```bash
docker save netmhcpan:4.2 | gzip > netmhcpan_4.2.tar.gz
docker save netmhc2pan:4.3 | gzip > netmhc2pan_4.3.tar.gz

# Upload to GCS
gsutil cp netmhcpan_4.2.tar.gz gs://your-bucket/docker/
gsutil cp netmhc2pan_4.3.tar.gz gs://your-bucket/docker/
```

To restore from backup:

```bash
docker load < netmhcpan_4.2.tar.gz
```

---

## Notes

- The download links provided by DTU are **personalized and time-limited**. Save your images immediately after building.
- This guide documents the interactive installation method (`docker commit`). A Dockerfile approximating this process is available in `docker/netmhcpan/Dockerfile` and `docker/netmhc2pan/Dockerfile`, but those are reconstructions and may require adjustments.
- The `peps-pipeline` scripts expect the images to be tagged exactly as `netmhcpan:4.2` and `netmhc2pan:4.3`.
