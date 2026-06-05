#!/bin/bash
# Verify MXC bubblewrap backend on Ubuntu Linux.
set -euo pipefail

MXC_CONFIG="${1:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MXC_CONFIG="${MXC_CONFIG:-${REPO_ROOT}/config/mxc/linux-bubblewrap-lab.json}"

if [[ ! -f "$MXC_CONFIG" ]]; then
  echo "ERROR: MXC config not found: $MXC_CONFIG" >&2
  exit 1
fi

echo "=== MXC Linux verification ==="

if ! command -v bwrap >/dev/null 2>&1; then
  echo "ERROR: bubblewrap (bwrap) not installed. Run: sudo apt install bubblewrap" >&2
  exit 1
fi
echo "OK  bubblewrap: $(command -v bwrap)"

userns="$(cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null || echo unknown)"
echo "    unprivileged_userns_clone=${userns}"
if [[ "$userns" != "1" ]]; then
  echo "WARN user namespaces may be restricted on this host" >&2
fi

if ! npm root -g >/dev/null 2>&1; then
  echo "ERROR: npm global root unavailable; install Node.js and @microsoft/mxc-sdk" >&2
  exit 1
fi

SDK_ROOT="$(npm root -g)/@microsoft/mxc-sdk"
if [[ ! -d "$SDK_ROOT" ]]; then
  echo "ERROR: @microsoft/mxc-sdk not installed globally" >&2
  exit 1
fi
echo "OK  @microsoft/mxc-sdk: $SDK_ROOT"

LXC_EXEC="$(find "$SDK_ROOT" -name lxc-exec -type f 2>/dev/null | head -1 || true)"
if [[ -z "$LXC_EXEC" ]]; then
  echo "ERROR: lxc-exec binary not found under $SDK_ROOT" >&2
  exit 1
fi
echo "OK  lxc-exec: $LXC_EXEC"

echo "=== Platform support (SDK) ==="
node --input-type=module -e "
import { getPlatformSupport } from '@microsoft/mxc-sdk';
const s = getPlatformSupport();
console.log(JSON.stringify(s, null, 2));
if (!s.isSupported) process.exit(2);
"

echo "=== Bubblewrap smoke run ==="
echo "Config: $MXC_CONFIG"
OUTPUT="$("$LXC_EXEC" "$MXC_CONFIG" 2>&1)" || {
  echo "ERROR: lxc-exec failed:" >&2
  echo "$OUTPUT" >&2
  exit 1
}
echo "$OUTPUT"
echo "=== MXC Linux verification passed ==="
