#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/coder}"
mkdir -p "$HOME/.local/share/code-server/extensions"

while IFS= read -r extension; do
  [[ -z "$extension" || "$extension" == \#* ]] && continue
  code-server --extensions-dir "$HOME/.local/share/code-server/extensions" \
    --install-extension "$extension"
done < /opt/developer-workspace/extensions.txt
