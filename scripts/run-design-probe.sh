#!/usr/bin/env bash
# run-design-probe.sh: run design-probe.js against a site with dev-browser.
# dev-browser scripts run in a QuickJS sandbox without access to environment variables, so this
# wrapper fills the URL into the script and pipes it to dev-browser.
# The probe clears cookies to see the site as a first-time visitor, so it always runs in its own
# dev-browser instance (default name "cmplz-probe"), never in the shared "default" instance and never
# against your real Chrome (--connect).
# Usage: bash scripts/run-design-probe.sh <URL> [extra dev-browser flags, e.g. --headless]
set -euo pipefail

URL="${1:-}"
[ -n "$URL" ] || { echo "Usage: bash scripts/run-design-probe.sh <URL> [dev-browser flags]"; exit 2; }
shift
case "$URL" in
  http://*|https://*) ;;
  *) echo "The URL must start with http:// or https://"; exit 2 ;;
esac
command -v dev-browser >/dev/null || { echo "dev-browser not found: npm install -g dev-browser && dev-browser install"; exit 2; }

HAS_BROWSER=0; HAS_TIMEOUT=0; PREV=""
for a in "$@"; do
  case "$a" in
    --connect|--connect=*) echo "Refusing --connect: the probe clears cookies and would log your own browser out of the site."; exit 2 ;;
    --browser=default) echo "Refusing --browser default: the probe clears cookies there; pick another name."; exit 2 ;;
    --browser|--browser=*) HAS_BROWSER=1 ;;
    --timeout|--timeout=*) HAS_TIMEOUT=1 ;;
  esac
  if [ "$PREV" = "--browser" ] && [ "$a" = "default" ]; then
    echo "Refusing --browser default: the probe clears cookies there; pick another name."; exit 2
  fi
  PREV="$a"
done
[ "$HAS_BROWSER" -eq 1 ] || set -- --browser cmplz-probe "$@"
[ "$HAS_TIMEOUT" -eq 1 ] || set -- --timeout 90 "$@"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 -I - "$URL" "$DIR/design-probe.js" <<'PY' | dev-browser "$@"
import json, sys
url, path = sys.argv[1], sys.argv[2]
src = open(path, encoding='utf-8').read()
token = '"REPLACE_WITH_SITE_URL/"'
if token not in src:
    sys.exit("design-probe.js: URL placeholder not found")
print(src.replace(token, json.dumps(url), 1))
PY
