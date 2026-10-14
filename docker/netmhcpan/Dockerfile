# Dockerfile — NetMHCpan 4.2 (MHC-I)
# Base: Ubuntu 24.04
#
# DISCLAIMER: This Dockerfile is a reconstruction from image inspection.
# The original image was built interactively. This file approximates
# the original environment but may require adjustments to build correctly.
#
# NOTE: NetMHCpan is licensed software from DTU Health Tech.
# You must download the tarball with your own academic license before building.
# License: https://services.healthtech.dtu.dk/services/NetMHCpan-4.2/
#
# Build:
#   Place netMHCpan-4.2.Linux.tar.gz in this directory, then:
#   docker build -t netmhcpan:4.2 .

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C
ENV NETMHCpan=/work/netMHCpan-4.2

RUN apt-get update && apt-get install -y \
    tcsh \
    perl \
    gawk \
    wget \
    tar \
    ghostscript \
    imagemagick \
    groff \
    nano \
    tree \
    ncurses-bin \
    fontconfig \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

COPY netMHCpan-4.2.Linux.tar.gz /work/
RUN tar -xzf netMHCpan-4.2.Linux.tar.gz \
    && rm netMHCpan-4.2.Linux.tar.gz

CMD ["/bin/bash"]
