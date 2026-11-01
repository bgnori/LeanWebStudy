FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        libsqlite3-dev \
        libwebsockets-dev \
        python3 \
    && rm -rf /var/lib/apt/lists/*

USER vscode
ENV PATH="/home/vscode/.elan/bin:${PATH}"
RUN curl -fsSL https://elan.lean-lang.org/elan-init.sh \
    | sh -s -- -y --default-toolchain none

COPY lean-toolchain /tmp/lean-toolchain
RUN elan toolchain install "$(cat /tmp/lean-toolchain)"
