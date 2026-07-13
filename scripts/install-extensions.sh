#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/coder}"
extensions_dir=${CODE_SERVER_EXTENSIONS_DIR:-$HOME/.local/share/code-server/extensions}
mkdir -p "$extensions_dir"

while IFS= read -r extension; do
  [[ -z "$extension" || "$extension" == \#* ]] && continue
  code-server --extensions-dir "$extensions_dir" \
    --install-extension "$extension"
done < /opt/developer-workspace/extensions.txt
