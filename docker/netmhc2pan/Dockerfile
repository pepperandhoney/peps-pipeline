# Dockerfile — NetMHC2pan 4.3 (MHC-II)
# Base: Ubuntu 22.04
#
# DISCLAIMER: This Dockerfile is a reconstruction from image inspection.
# The original image was built interactively. This file approximates
# the original environment but may require adjustments to build correctly.
#
# NOTE: NetMHCIIpan is licensed software from DTU Health Tech.
# You must download the tarball with your own academic license before building.
# License: https://services.healthtech.dtu.dk/services/NetMHCIIpan-4.3/
#
# Build:
#   Place netMHCIIpan-4.3.Linux.tar.gz in this directory, then:
#   docker build -t netmhc2pan:4.3 .

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C
ENV NETMHCIIpan=/work/netMHCIIpan-4.3

RUN apt-get update && apt-get install -y \
    tcsh \
    perl \
    gawk \
    wget \
    tar \
    nano \
    tree \
    ncurses-bin \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

COPY netMHCIIpan-4.3.Linux.tar.gz /work/
RUN tar -xzf netMHCIIpan-4.3.Linux.tar.gz \
    && rm netMHCIIpan-4.3.Linux.tar.gz

CMD ["/bin/bash"]
