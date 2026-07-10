# syntax=docker/dockerfile:1.7
ARG CODE_SERVER_VERSION=4.127.0
FROM codercom/code-server:${CODE_SERVER_VERSION}

USER root

ARG MISE_VERSION=2026.7.3
ARG SOPS_VERSION=3.13.1
ARG KUBECTL_VERSION=1.34.1
ARG HELM_VERSION=3.18.4
ARG KUSTOMIZE_VERSION=5.7.1
ARG TOFU_VERSION=1.10.6
ARG CHEZMOI_VERSION=2.65.1

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    age ansible bash-completion ca-certificates curl fd-find git gnupg jq less \
    make openssh-client python3 python3-venv ripgrep shellcheck sudo tmux unzip \
    wget yq \
 && rm -rf /var/lib/apt/lists/*

# Standalone binary downloads are pinned by version. SHA-256 verification must be
# added before the first production release; see docs/BOOTSTRAP.md.
RUN curl -fsSL "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-x64" \
      -o /usr/local/bin/mise \
 && chmod 0755 /usr/local/bin/mise

RUN curl -fsSL "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" \
      -o /usr/local/bin/sops \
 && chmod 0755 /usr/local/bin/sops

RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl \
 && chmod 0755 /usr/local/bin/kubectl

RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tgz \
 && tar -xzf /tmp/helm.tgz -C /tmp \
 && install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm \
 && rm -rf /tmp/helm.tgz /tmp/linux-amd64

RUN curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" -o /tmp/kustomize.tgz \
 && tar -xzf /tmp/kustomize.tgz -C /usr/local/bin \
 && chmod 0755 /usr/local/bin/kustomize \
 && rm /tmp/kustomize.tgz

RUN curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.zip" -o /tmp/tofu.zip \
 && unzip /tmp/tofu.zip -d /tmp/tofu \
 && install -m 0755 /tmp/tofu/tofu /usr/local/bin/tofu \
 && rm -rf /tmp/tofu.zip /tmp/tofu

RUN curl -fsSL "https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux_amd64.tar.gz" -o /tmp/chezmoi.tgz \
 && tar -xzf /tmp/chezmoi.tgz -C /tmp \
 && install -m 0755 /tmp/chezmoi /usr/local/bin/chezmoi \
 && rm /tmp/chezmoi.tgz

COPY scripts/ /usr/local/lib/developer-workspace/
COPY config/code-server/config.yaml /etc/code-server/config.yaml
COPY extensions/baseline.txt /opt/developer-workspace/extensions.txt

RUN chmod -R a+rX /usr/local/lib/developer-workspace /opt/developer-workspace \
 && /usr/local/lib/developer-workspace/install-extensions.sh

USER 1000
ENV SHELL=/bin/bash \
    MISE_DATA_DIR=/home/coder/.local/share/mise \
    MISE_CACHE_DIR=/home/coder/.cache/mise \
    BW_SERVER=https://vault.skunklabs.uk

WORKDIR /workspaces
ENTRYPOINT ["/usr/local/lib/developer-workspace/entrypoint.sh"]
CMD ["code-server", "--config", "/etc/code-server/config.yaml", "/workspaces"]
