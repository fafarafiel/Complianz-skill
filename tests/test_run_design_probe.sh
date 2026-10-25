#!/usr/bin/env bash
# Offline test of scripts/run-design-probe.sh with a stub dev-browser that records its arguments
# and the script it receives. Checks URL substitution and browser isolation.
# Usage: bash tests/test_run_design_probe.sh   (run from the repository root)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUB=$(mktemp -d "${TMPDIR:-/tmp}/cmplz-stub.XXXXXX")
trap 'rm -rf "$STUB"' EXIT
FAILURES=0

cat > "$STUB/dev-browser" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$STUB/args"
cat > "$STUB/script.js"
EOF
chmod +x "$STUB/dev-browser"

check() { # name, condition result (0 = ok)
  if [ "$2" -eq 0 ]; then echo "PASS  $1"; else echo "FAIL  $1"; FAILURES=$((FAILURES + 1)); fi
}
run() { rm -f "$STUB/args" "$STUB/script.js"; PATH="$STUB:$PATH" /bin/bash "$ROOT/scripts/run-design-probe.sh" "$@" >/dev/null 2>&1; }

run "https://example.test/"; rc=$?
check "runs with a URL" "$rc"
grep -q 'const SITE_URL = "https://example.test/";' "$STUB/script.js" 2>/dev/null; check "URL filled into the script" $?
grep -q 'REPLACE_WITH_SITE_URL' "$STUB/script.js" 2>/dev/null; [ $? -ne 0 ]; check "no placeholder left" $?
tr '\n' ' ' < "$STUB/args" 2>/dev/null | grep -q -- '--browser cmplz-probe'; check "isolated instance by default" $?

run "https://example.test/" --browser my-test --headless
tr '\n' ' ' < "$STUB/args" | grep -q -- '--browser my-test --headless'; check "custom --browser and flags passed through" $?
grep -c -- 'cmplz-probe' "$STUB/args" | grep -q '^0$'; check "no default instance when --browser is given" $?

run "https://example.test/" --connect; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$STUB/args" ]; check "--connect refused before dev-browser runs" $?

run "https://example.test/" --browser default; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$STUB/args" ]; check "--browser default refused" $?
run "https://example.test/" --browser=default; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$STUB/args" ]; check "--browser=default refused" $?

run "https://example.test/" --timeout 200
[ "$(grep -c -- '--timeout' "$STUB/args")" -eq 1 ] && grep -q '^200$' "$STUB/args"; check "user --timeout passed once, no default added" $?
run "https://example.test/"
tr '\n' ' ' < "$STUB/args" | grep -q -- '--timeout 90'; check "default --timeout 90 otherwise" $?

run "example.test"; rc=$?
[ "$rc" -eq 2 ]; check "URL without scheme refused" $?

echo
[ "$FAILURES" -eq 0 ] && echo "all checks passed" || echo "$FAILURES check(s) FAILED"
exit $(( FAILURES > 0 ))
