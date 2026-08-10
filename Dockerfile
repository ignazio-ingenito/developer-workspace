# syntax=docker/dockerfile:1.7
ARG CODE_SERVER_VERSION=4.131.0

FROM codercom/code-server:${CODE_SERVER_VERSION}

USER root

ARG MISE_VERSION=2026.7.3
ARG OH_MY_BASH_REF=627913b75855036cb5af2f3ad130c66a335e7382

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

# Keep only the operating-system bootstrap in the immutable image. Fast-moving
# developer CLIs are installed by mise in the persistent, writable home.
# Chromium itself remains project-managed; the image provides only the Debian
# runtime and fonts required to execute Playwright's downloaded browser.
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
    bash-completion ca-certificates curl dnsutils git gnupg less make openssh-client \
    sudo tmux unzip util-linux wget xz-utils \
    fonts-liberation fonts-noto-color-emoji fonts-unifont libfontconfig1 libfreetype6 \
    libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 \
    libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 \
    libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
    libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
 && apt-get purge -y vim-tiny vim-common xxd \
 && rm -f /usr/local/bin/fixuid \
 && rm -rf /etc/fixuid /var/lib/apt/lists/*

COPY scripts/download-verified.sh /usr/local/bin/download-verified
RUN chmod 0755 /usr/local/bin/download-verified

# This is a recovery seed, not the active mise installation. The launcher
# copies it into ~/.local/bin on first use, where mise can update itself.
RUN download-verified \
      "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-x64" \
      "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/SHASUMS256.txt" \
      "mise-v${MISE_VERSION}-linux-x64" \
      /tmp/mise \
 && install -m 0755 /tmp/mise /opt/mise-bootstrap \
 && rm /tmp/mise

RUN git clone https://github.com/ohmybash/oh-my-bash.git /opt/oh-my-bash \
 && git -C /opt/oh-my-bash checkout "${OH_MY_BASH_REF}" \
 && rm -rf /opt/oh-my-bash/.git

COPY scripts/ /usr/local/lib/developer-workspace/
COPY config/code-server/config.yaml /etc/code-server/config.yaml
COPY config/shell/bashrc /opt/developer-workspace/bashrc
COPY config/tmux/tmux.conf /opt/developer-workspace/tmux.conf
COPY config/mise/workspace-tools.toml /opt/developer-workspace/mise-workspace-tools.toml
COPY extensions/baseline.txt /opt/developer-workspace/extensions.txt

RUN CODE_SERVER_EXTENSIONS_DIR=/opt/developer-workspace/code-server-extensions \
      /usr/local/lib/developer-workspace/install-extensions.sh \
 && chmod -R a+rX /usr/local/lib/developer-workspace /opt/developer-workspace /opt/oh-my-bash \
 && chmod 0755 /usr/local/lib/developer-workspace/*.sh \
 && ln -s /usr/local/lib/developer-workspace/workspace-doctor.sh /usr/local/bin/workspace-doctor \
 && ln -s /usr/local/lib/developer-workspace/workspace-tmux.sh /usr/local/bin/workspace-tmux \
 && ln -s /usr/local/lib/developer-workspace/workspace-tools.sh /usr/local/bin/workspace-tools \
 && ln -s /usr/local/lib/developer-workspace/mise-launcher.sh /usr/local/bin/mise \
 && ln -s /usr/local/lib/developer-workspace/codex-launcher.sh /usr/local/bin/codex

ENV HOME=/home/coder \
    SHELL=/bin/bash \
    MISE_DATA_DIR=/home/coder/.local/share/mise \
    MISE_CACHE_DIR=/home/coder/.cache/mise \
    MISE_GLOBAL_CONFIG_FILE=/opt/developer-workspace/mise-workspace-tools.toml \
    MISE_BOOTSTRAP_BINARY=/opt/mise-bootstrap \
    NPM_CONFIG_CACHE=/home/coder/.cache/npm \
    CODEX_INSTALL_DIR=/home/coder/.local/libexec/codex \
    CODEX_AUTO_UPDATE=true \
    CODEX_AUTO_UPDATE_INTERVAL=21600 \
    CODEX_AUTO_UPDATE_FAILURE_BACKOFF=900 \
    CODEX_AUTO_UPDATE_TIMEOUT=120 \
    BW_SERVER=https://vault.skunklabs.uk

USER 1000

WORKDIR /workspaces
ENTRYPOINT ["/usr/local/lib/developer-workspace/entrypoint.sh"]
CMD ["code-server", "--config", "/etc/code-server/config.yaml", "/workspaces"]
