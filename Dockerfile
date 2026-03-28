FROM rust:1.85-slim-bookworm

# System deps: git, gh CLI, curl (for Claude Code)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    pkg-config \
    curl \
    sudo \
    jq \
    ca-certificates \
    gnupg \
  && mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/github-cli.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/github-cli.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y gh \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Non-root user for safety
RUN useradd -m -s /bin/bash -u 1000 dev \
  && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/dev

# Pre-create config directories
RUN mkdir -p /home/dev/.config /home/dev/.claude /home/dev/.cargo \
  && chown -R dev:dev /home/dev/.config /home/dev/.claude /home/dev/.cargo

# Copy cargo registry/config from rust base image to dev user
RUN cp -r /usr/local/cargo/. /home/dev/.cargo/ \
  && chown -R dev:dev /home/dev/.cargo

USER dev
ENV CARGO_HOME=/home/dev/.cargo
ENV PATH="/home/dev/.cargo/bin:/home/dev/.local/bin:${PATH}"

# Install Claude Code (bundles its own runtime — no Node needed)
RUN curl -fsSL https://claude.ai/install.sh | bash

WORKDIR /workspace

# Pre-fetch deps (best-effort — won't fail the build if code isn't ready)
COPY --chown=dev:dev Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && echo "" > src/lib.rs \
    && cargo build --release 2>/dev/null || true \
    && rm -rf src

# Copy source — build happens inside the running container, not at image build time.
# This allows the Dockerfile to succeed even when the code is mid-refactor.
COPY --chown=dev:dev . .

ENTRYPOINT ["/workspace/scripts/docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
