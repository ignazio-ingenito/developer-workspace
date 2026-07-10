#!/usr/bin/env bash
set -euo pipefail

while IFS= read -r extension; do
  [[ -z "$extension" || "$extension" == \#* ]] && continue
  code-server --install-extension "$extension"
done < /opt/developer-workspace/extensions.txt
