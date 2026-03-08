FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV CHEZMOI_NAME="Test User"
ENV CHEZMOI_EMAIL="test@example.com"

# Base dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    zsh \
    ca-certificates \
    libatomic1 \
    && rm -rf /var/lib/apt/lists/*

# Install bats-core from source (system package is often outdated)
RUN git clone --depth=1 https://github.com/bats-core/bats-core.git /opt/bats-core \
    && /opt/bats-core/install.sh /usr/local \
    && rm -rf /opt/bats-core

# Create non-root user — mirrors the "no sudo" Linux constraint
RUN useradd -m -s /bin/zsh user
USER user
WORKDIR /home/user
