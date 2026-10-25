#!/usr/bin/env bash
# Offline test of scripts/verify.sh: serves HTML fixtures on localhost and checks the verdicts.
# Usage: bash tests/test_verify.sh   (run from the repository root)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX=$(mktemp -d "${TMPDIR:-/tmp}/cmplz-fixtures.XXXXXX")
PORT=$(( 20000 + RANDOM % 20000 ))
FAILURES=0

cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; fi
  rm -rf "$FIX"
}
trap cleanup EXIT

BANNER='<div id="cmplz-cookiebanner-1-optin" class="cmplz-cookiebanner cmplz-hidden banner-1 optin cmplz-bottom-right" aria-labelledby="cmplz-header-1-optin"><a class="cmplz-link cookie-statement" href="/legal/cookie-policy/?cmplz_region_redirect=true">Cookie policy</a><a class="cmplz-link privacy-statement" href="/privacy-statement/">Privacy</a></div><script src="/wp-content/plugins/complianz/complianz.js"></script>'
mkdir -p "$FIX/legal/cookie-policy" && echo "<html>policy</html>" > "$FIX/legal/cookie-policy/index.html"
mkdir -p "$FIX/moved" && echo "<html><body>$BANNER</body></html>" > "$FIX/moved/index.html"
cat > "$FIX/blocked.html" <<EOF
<html><head><link rel='dns-prefetch' href='//fonts.googleapis.com' />
<link rel="stylesheet" data-category="marketing" data-href="https://fonts.googleapis.com/css?family=Nunito" />
<script type="text/plain" data-category="statistics">(function(){var s='https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX';})();</script>
<script type="text/plain" data-service="facebook" data-category="marketing">fbq('init','000');</script>
</head><body>$BANNER</body></html>
EOF
cat > "$FIX/active.html" <<EOF
<html><head><script>(function(){var s='https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX';})();</script>
</head><body>$BANNER</body></html>
EOF
cat > "$FIX/hint-only.html" <<EOF
<html><head><link rel="preconnect" href="https://fonts.googleapis.com" /></head><body>$BANNER</body></html>
EOF
cat > "$FIX/active-font.html" <<EOF
<html><head><link rel='dns-prefetch' href='//fonts.googleapis.com' />
<link rel='stylesheet' href='https://fonts.googleapis.com/css?family=Nunito' /></head><body>$BANNER</body></html>
EOF
cat > "$FIX/mixed.html" <<EOF
<html><head><script type="text/plain" data-category="statistics">var a='https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX';</script>
<script>var b='https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX';</script>
</head><body>$BANNER</body></html>
EOF
cat > "$FIX/outside.html" <<EOF
<html><head><script type="text/plain" data-category="marketing">var x=1;</script>
<style>@import url(https://fonts.googleapis.com/css?family=Nunito);</style>
<iframe data-src-cmplz="https://www.google.com/maps/embed?pb=1" data-category="marketing"></iframe>
</head><body>$BANNER</body></html>
EOF
cat > "$FIX/iframe-live.html" <<EOF
<html><head></head><body><iframe src="https://www.google.com/maps/embed?pb=1"></iframe>$BANNER</body></html>
EOF
cat > "$FIX/string-trap.html" <<EOF
<html><head><script>var tpl='<link rel="x">'; var s='https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX';</script>
</head><body>$BANNER</body></html>
EOF
cat > "$FIX/edge.html" <<EOF
<html><head>
<!-- <script src="https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX"></script> -->
<SCRIPT TYPE="TEXT/PLAIN" data-category="marketing">fbq('init','000');</SCRIPT>
<link rel=stylesheet data-category=marketing data-href=https://fonts.googleapis.com/css?family=Nunito>
<noscript>
<iframe src="https://www.googletagmanager.com/ns.html?id=GTM-XXXXXXX"></iframe>
</noscript>
</head><body>$BANNER</body></html>
EOF
cat > "$FIX/img-pixel.html" <<EOF
<html><head></head><body><img src="https://www.facebook.com/tr?id=000&ev=PageView" height="1" width="1">$BANNER</body></html>
EOF
cat > "$FIX/comment-trap.html" <<EOF
<html><head><script>var marker = "<!--";</script>
<script async src="https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX"></script>
</head><body>$BANNER</body></html>
EOF
cat > "$FIX/old-style.html" <<EOF
<html><head><script><!--
(function(){var s='https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX';})();
//--></script></head><body>$BANNER</body></html>
EOF
cat > "$FIX/noscript-cross.html" <<EOF
<html><head><noscript><img src="/a.png"></noscript>
<script type="text/plain" data-category="statistics" data-note="a>b">var s='https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX';</script>
<noscript><img src="/b.png"></noscript></head><body>$BANNER</body></html>
EOF
cat > "$FIX/lazy.html" <<EOF
<html><head><link rel="stylesheet" data-pmdelayedstyle="https://fonts.googleapis.com/css?family=Nunito"></head>
<body><iframe data-lazyloaded="1" src="about:blank" data-src="https://www.google.com/maps/embed?pb=1"></iframe>
<iframe loading="lazy" data-lazy-src="https://www.youtube.com/embed/abc"></iframe>$BANNER</body></html>
EOF
cat > "$FIX/meta-trap.html" <<EOF
<html><head><meta name="description" content="Best deals <!-- today only">
<script async src="https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX"></script></head><body>$BANNER</body></html>
EOF
cat > "$FIX/embed.html" <<EOF
<html><head></head><body><embed src="https://www.youtube.com/embed/abc">$BANNER</body></html>
EOF
cat > "$FIX/json-config.html" <<EOF
<html><head><script type="application/json" id="cfg">{"gtm":"https://www.googletagmanager.com/gtm.js"}</script></head><body>$BANNER</body></html>
EOF
cat > "$FIX/data-type.html" <<EOF
<html><head><script data-type="application/json" src="https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX"></script></head><body>$BANNER</body></html>
EOF
cat > "$FIX/data-type-plain.html" <<EOF
<html><head><script data-type="text/plain" src="https://www.googletagmanager.com/gtm.js?id=GTM-XXXXXXX"></script></head><body>$BANNER</body></html>
EOF
cat > "$FIX/optout.html" <<EOF
<html><head></head><body><div id="cmplz-cookiebanner-1-optout" class="cmplz-cookiebanner cmplz-hidden banner-1 optout cmplz-bottom-right"></div><script src="/wp-content/plugins/complianz/complianz.js"></script><link rel="stylesheet" href="/wp-content/uploads/complianz/css/banner-1-optin.css"></body></html>
EOF
cat > "$FIX/offsite-policy.html" <<EOF
<html><head></head><body>$BANNER<a href="https://policies.example.invalid/privacy-policy/">Partner privacy</a></body></html>
EOF
cat > "$FIX/policy-redirect.html" <<EOF
<html><head></head><body>$BANNER<a href="/legal/cookie-policy">Cookies</a></body></html>
EOF
cat > "$FIX/no-banner.html" <<EOF
<html><head></head><body>plain page</body></html>
EOF

(cd "$FIX" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
SERVER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.3; done

expect() { # name, expected exit code, grep pattern that must appear, page, trackers...
  local name="$1" code="$2" pattern="$3" page="$4"; shift 4
  local out rc
  if [ "$page" = "NONE" ]; then
    out=$(/bin/bash "$ROOT/scripts/verify.sh" 2>&1); rc=$?
  else
    out=$(/bin/bash "$ROOT/scripts/verify.sh" "http://127.0.0.1:$PORT/$page" "$@" 2>&1); rc=$?
  fi
  if [ "$rc" = "$code" ] && printf '%s' "$out" | grep -q -- "$pattern"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name (exit $rc, expected $code; pattern: $pattern)"; printf '%s\n' "$out" | sed 's/^/      /'
    FAILURES=$((FAILURES + 1))
  fi
}

expect_not() { # name, pattern that must NOT appear, page, trackers...
  local name="$1" pattern="$2" page="$3"; shift 3
  local out
  out=$(/bin/bash "$ROOT/scripts/verify.sh" "http://127.0.0.1:$PORT/$page" "$@" 2>&1)
  if printf '%s' "$out" | grep -q -- "$pattern"; then
    echo "FAIL  $name (unexpected: $pattern)"; FAILURES=$((FAILURES + 1))
  else
    echo "PASS  $name"
  fi
}

expect "all trackers blocked → PASS"              0 "tracker blocked until consent: googletagmanager.com/gtm.js" blocked.html
expect "blocked Google Fonts behind a dns hint"   0 "tracker blocked until consent: fonts.googleapis" blocked.html
expect "inline GTM loader active → FAIL"          1 "tracker ACTIVE before consent: googletagmanager.com/gtm.js" active.html
expect "blocked copy then a live copy → FAIL"     1 "1 live, 1 blocked" mixed.html googletagmanager.com/gtm.js
expect "resource hint only → warning, not FAIL"   0 "only resource hints" hint-only.html fonts.googleapis
expect "inline @import after a blocked script → not a PASS" 0 "not classified: fonts.googleapis" outside.html fonts.googleapis
expect "Complianz-blocked iframe → blocked"        0 "tracker blocked until consent: google.com/maps" outside.html google.com/maps
expect "live iframe → FAIL"                        1 "tracker ACTIVE before consent: google.com/maps" iframe-live.html google.com/maps
expect "'<link>' inside a JS string → still FAIL"  1 "tracker ACTIVE before consent: googletagmanager.com/gtm.js" string-trap.html googletagmanager.com/gtm.js
expect "unclassified occurrence flagged in result" 0 "with unclassified occurrences" outside.html fonts.googleapis
expect "redirect is followed (301 to the page)"    0 "banner container" moved
expect "live font stylesheet after a hint → FAIL" 1 "tracker ACTIVE before consent: fonts.googleapis" active-font.html fonts.googleapis
expect "no banner → FAIL"                         1 "no cmplz-cookiebanner container" no-banner.html
expect "tag inside an HTML comment is ignored"     0 "tracker not present in the HTML: googletagmanager.com/gtm.js" edge.html googletagmanager.com/gtm.js
expect "upper-case TYPE=TEXT/PLAIN is blocked"     0 "tracker blocked until consent: fbq('init'" edge.html "fbq('init'"
expect "unquoted data-href is blocked"             0 "tracker blocked until consent: fonts.googleapis" edge.html fonts.googleapis
expect "noscript iframe → fallback warning only"   0 "only in <noscript> fallbacks: googletagmanager.com/ns.html" edge.html googletagmanager.com/ns.html
expect "multi-line noscript GTM is reported"       0 "noscript GTM fallback present" edge.html
expect "live img pixel → FAIL"                     1 "tracker ACTIVE before consent: facebook.com/tr" img-pixel.html facebook.com/tr
expect "'<!--' in a JS string, then live GTM → FAIL" 1 "tracker ACTIVE before consent: googletagmanager.com/gtm.js" comment-trap.html googletagmanager.com/gtm.js
expect "old-style <!-- --> inside a live script → FAIL" 1 "tracker ACTIVE before consent: googletagmanager.com/gtm.js" old-style.html googletagmanager.com/gtm.js
expect "'>' inside an attribute stays blocked"     0 "tracker blocked until consent: googletagmanager.com/gtm.js" noscript-cross.html googletagmanager.com/gtm.js
expect_not "no noscript warning across separate blocks" "noscript GTM fallback present" noscript-cross.html
expect "LiteSpeed lazy iframe (data-src) → FAIL"   1 "held back by a lazy-loader or optimizer (data-src)" lazy.html google.com/maps
expect "WP Rocket lazy iframe (data-lazy-src) → FAIL" 1 "held back by a lazy-loader or optimizer (data-lazy-src)" lazy.html youtube.com/embed
expect "Perfmatters delayed style → FAIL"          1 "held back by a lazy-loader or optimizer (data-pmdelayedstyle)" lazy.html fonts.googleapis
expect "'<!--' inside a meta attribute, live GTM → FAIL" 1 "tracker ACTIVE before consent: googletagmanager.com/gtm.js" meta-trap.html googletagmanager.com/gtm.js
expect "live <embed> → FAIL"                       1 "tracker ACTIVE before consent: youtube.com/embed" embed.html youtube.com/embed
expect "URL inside a JSON data script → not classified" 0 "not classified: googletagmanager.com/gtm.js" json-config.html googletagmanager.com/gtm.js
expect "data-type attribute does not hide a live script" 1 "tracker ACTIVE before consent: googletagmanager.com/gtm.js" data-type.html googletagmanager.com/gtm.js
expect "data-type=text/plain is not a block"       1 "tracker ACTIVE before consent: googletagmanager.com/gtm.js" data-type-plain.html googletagmanager.com/gtm.js
expect "opt-in marker detected from banner class"  0 "mode: opt-in" blocked.html
expect "opt-out banner: no opt-in marker warning"  0 "no opt-in marker" optout.html
expect "policy link with a query string → 200"    0 "policy link → 200: http://127.0.0.1:$PORT/legal/cookie-policy/?cmplz_region_redirect=true" blocked.html
expect "missing policy page → warning only"       0 "policy link → 404: http://127.0.0.1:$PORT/privacy-statement/" blocked.html
expect "same-site policy redirect is followed"    0 "policy link → 200: http://127.0.0.1:$PORT/legal/cookie-policy" policy-redirect.html
expect "off-site policy link is listed, not requested" 0 "policy link on another site (not checked): https://policies.example.invalid/privacy-policy/" offsite-policy.html
expect "usage error without URL"                  2 "Usage" NONE

echo
[ "$FAILURES" -eq 0 ] && echo "all checks passed" || echo "$FAILURES check(s) FAILED"
exit $(( FAILURES > 0 ))
