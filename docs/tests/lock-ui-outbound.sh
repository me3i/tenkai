#!/usr/bin/env bash
# The lock's look must not talk to anything: no outbound call, no asset that
# comes from the network, no font that was bundled without a licence.
#
# The check proves itself first: a file that does have such a reference must
# be caught, or the check is worthless.
set -uo pipefail
MEI="$(cd "$(dirname "$0")/../.." && pwd)"
LOCK_DIR="$MEI/src/ryoku/shell/quickshell/shell/modules/lock"
fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }

# What would count as reaching out.
PATTERN='XMLHttpRequest|https?://|fetch\(|WebSocket|source[[:space:]]*:[[:space:]]*"http'

echo "lock ui outbound check: $(date -Is)"

echo
echo "=== A: the check can fail ==="
tmp="$MEI/.run/lock-ui-outbound-selftest.qml"
mkdir -p "$MEI/.run"
printf 'Item { property url u: "https://example.invalid/x.png" }\n' > "$tmp"
if grep -qE "$PATTERN" "$tmp"; then
  ok "the pattern catches an outbound reference"
else
  bad "the pattern does not catch an outbound reference: the check is worthless"
fi
rm -f "$tmp"

echo
echo "=== B: the lock's own files reach out to nothing ==="
hits="$(grep -rnE "$PATTERN" "$LOCK_DIR" 2>/dev/null | head -5)"
if [ -z "$hits" ]; then
  ok "the lock's QML files have no outbound call and no network asset"
else
  bad "the lock's QML files reach out: $hits"
fi

echo
echo "=== C: the lock ships no asset ==="
assets="$(find "$LOCK_DIR" -type f ! -name '*.qml' 2>/dev/null | head -5)"
if [ -z "$assets" ]; then
  ok "the lock's folder holds QML only: no font, no image, no licence question"
else
  bad "the lock's folder ships assets: $assets"
fi

echo
echo "=== D: the greeter's own parts were not brought along ==="
if grep -rn "SddmComponents\|SddmQmlTheme" "$LOCK_DIR" 2>/dev/null | head -3 | grep -q .; then
  bad "the lock's QML still uses the greeter's components"
else
  ok "the lock's QML does not use the greeter's components"
fi

[ "$fail" = 0 ] && echo "LOCK UI OUTBOUND: PASS" || echo "LOCK UI OUTBOUND: FAIL"
exit $fail
