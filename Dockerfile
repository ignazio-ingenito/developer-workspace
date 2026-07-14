# syntax=docker/dockerfile:1.7
ARG CODE_SERVER_VERSION=4.127.0
ARG NODE_VERSION=22.17.0

FROM node:${NODE_VERSION}-bookworm-slim AS node

FROM codercom/code-server:${CODE_SERVER_VERSION}

USER root

ARG MISE_VERSION=2026.7.3
ARG SOPS_VERSION=3.13.1
ARG KUBECTL_VERSION=1.34.1
ARG HELM_VERSION=3.18.4
ARG KUSTOMIZE_VERSION=5.7.1
ARG TOFU_VERSION=1.10.6
ARG CHEZMOI_VERSION=2.65.1
ARG BITWARDEN_CLI_VERSION=2026.6.0
ARG OH_MY_BASH_REF=627913b75855036cb5af2f3ad130c66a335e7382

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    age ansible bash-completion ca-certificates curl fd-find git gnupg jq less \
    make openssh-client python3 python3-venv ripgrep shellcheck sudo tmux unzip \
    util-linux wget yq \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && npm install --global \
      "@bitwarden/cli@${BITWARDEN_CLI_VERSION}" \
 && npm cache clean --force

COPY scripts/download-verified.sh /usr/local/bin/download-verified
RUN chmod 0755 /usr/local/bin/download-verified

RUN download-verified \
      "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-x64" \
      "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/SHASUMS256.txt" \
      "mise-v${MISE_VERSION}-linux-x64" \
      /tmp/mise \
 && install -m 0755 /tmp/mise /usr/local/bin/mise \
 && rm /tmp/mise

RUN download-verified \
      "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" \
      "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.checksums.txt" \
      "sops-v${SOPS_VERSION}.linux.amd64" \
      /tmp/sops \
 && install -m 0755 /tmp/sops /usr/local/bin/sops \
 && rm /tmp/sops

RUN download-verified \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" \
      kubectl \
      /tmp/kubectl \
 && install -m 0755 /tmp/kubectl /usr/local/bin/kubectl \
 && rm /tmp/kubectl

RUN download-verified \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
      "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" \
      "helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
      /tmp/helm.tgz \
 && tar -xzf /tmp/helm.tgz -C /tmp \
 && install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm \
 && rm -rf /tmp/helm.tgz /tmp/linux-amd64

RUN download-verified \
      "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
      "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/checksums.txt" \
      "kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
      /tmp/kustomize.tgz \
 && tar -xzf /tmp/kustomize.tgz -C /usr/local/bin \
 && chmod 0755 /usr/local/bin/kustomize \
 && rm /tmp/kustomize.tgz

RUN download-verified \
      "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.zip" \
      "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" \
      "tofu_${TOFU_VERSION}_linux_amd64.zip" \
      /tmp/tofu.zip \
 && unzip /tmp/tofu.zip -d /tmp/tofu \
 && install -m 0755 /tmp/tofu/tofu /usr/local/bin/tofu \
 && rm -rf /tmp/tofu.zip /tmp/tofu

RUN download-verified \
      "https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux_amd64.tar.gz" \
      "https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_checksums.txt" \
      "chezmoi_${CHEZMOI_VERSION}_linux_amd64.tar.gz" \
      /tmp/chezmoi.tgz \
 && tar -xzf /tmp/chezmoi.tgz -C /tmp \
 && install -m 0755 /tmp/chezmoi /usr/local/bin/chezmoi \
 && rm /tmp/chezmoi.tgz

RUN git clone https://github.com/ohmybash/oh-my-bash.git /opt/oh-my-bash \
 && git -C /opt/oh-my-bash checkout "${OH_MY_BASH_REF}" \
 && rm -rf /opt/oh-my-bash/.git

COPY scripts/ /usr/local/lib/developer-workspace/
COPY config/code-server/config.yaml /etc/code-server/config.yaml
COPY config/shell/bashrc /opt/developer-workspace/bashrc
COPY config/tmux/tmux.conf /opt/developer-workspace/tmux.conf
COPY extensions/baseline.txt /opt/developer-workspace/extensions.txt

RUN CODE_SERVER_EXTENSIONS_DIR=/opt/developer-workspace/code-server-extensions \
      /usr/local/lib/developer-workspace/install-extensions.sh \
 && chmod -R a+rX /usr/local/lib/developer-workspace /opt/developer-workspace /opt/oh-my-bash \
 && chmod 0755 /usr/local/lib/developer-workspace/*.sh \
 && ln -s /usr/local/lib/developer-workspace/workspace-doctor.sh /usr/local/bin/workspace-doctor \
 && ln -s /usr/local/lib/developer-workspace/workspace-tmux.sh /usr/local/bin/workspace-tmux \
 && ln -s /usr/local/lib/developer-workspace/workspace-tools.sh /usr/local/bin/workspace-tools \
 && ln -s /usr/local/lib/developer-workspace/codex-launcher.sh /usr/local/bin/codex

ENV HOME=/home/coder \
    SHELL=/bin/bash \
    MISE_DATA_DIR=/home/coder/.local/share/mise \
    MISE_CACHE_DIR=/home/coder/.cache/mise \
    CODEX_INSTALL_DIR=/home/coder/.local/libexec/codex \
    CODEX_AUTO_UPDATE=true \
    CODEX_AUTO_UPDATE_INTERVAL=21600 \
    CODEX_AUTO_UPDATE_FAILURE_BACKOFF=900 \
    BW_SERVER=https://vault.skunklabs.uk

USER 1000

WORKDIR /workspaces
ENTRYPOINT ["/usr/local/lib/developer-workspace/entrypoint.sh"]
CMD ["code-server", "--config", "/etc/code-server/config.yaml", "/workspaces"]
