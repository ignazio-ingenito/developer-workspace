#!/usr/bin/env bash
set -euo pipefail

playwright_version=${PLAYWRIGHT_ACCEPTANCE_VERSION:-1.61.0}
test_root=$(mktemp -d)

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

# Install only Node from the normal workspace mise baseline. The browser and the
# Playwright package live exclusively in this disposable CI container.
mise install node
eval "$(mise activate bash)"

command -v node >/dev/null
command -v npm >/dev/null
test "$(id -u)" != "0"

export PLAYWRIGHT_BROWSERS_PATH="$test_root/ms-playwright"
npm install \
  --prefix "$test_root" \
  --no-save \
  --no-package-lock \
  "playwright@${playwright_version}"

"$test_root/node_modules/.bin/playwright" install chromium

NODE_PATH="$test_root/node_modules" node <<'NODE'
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.setContent('<title>developer-workspace-playwright-ok</title><h1>ok</h1>');

  const title = await page.title();
  if (title !== 'developer-workspace-playwright-ok')
    throw new Error(`unexpected page title: ${title}`);

  await browser.close();
  console.log('playwright chromium acceptance passed');
})().catch(error => {
  console.error(error);
  process.exit(1);
});
NODE
