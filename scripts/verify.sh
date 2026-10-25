#!/usr/bin/env bash
# verify.sh: curl-based check of a Complianz deployment (no browser).
# Usage: bash verify.sh <URL> [tracker-substring ...]
#   e.g.: bash verify.sh https://example.com googletagmanager.com/gtm.js "fbq('init'" fonts.googleapis
# Without trackers it checks the defaults: gtm.js, gtag/js, fbq('init', connect.facebook.net, fonts.googleapis.
# Exit 0 = every check PASS; exit 1 = at least one FAIL; exit 2 = usage error.
# Set CMPLZ_INSECURE=1 to skip TLS verification (staging with a self-signed certificate only).
# NOTE: HTML layer only. Full E2E (accept / deny + network + screenshot): golden-path.md section 4.

set -u
URL="${1:-}"
[ -z "$URL" ] && { echo "Usage: bash verify.sh <URL> [tracker-substring ...]"; exit 2; }
shift || true
TRACKERS=("$@")
[ ${#TRACKERS[@]} -eq 0 ] && TRACKERS=("googletagmanager.com/gtm.js" "googletagmanager.com/gtag/js" "fbq('init'" "connect.facebook.net" "fonts.googleapis")

UA="Mozilla/5.0 (cmplz-verify)"
CURL_OPTS=(-s -m 30 -A "$UA")
[ "${CMPLZ_INSECURE:-0}" = "1" ] && CURL_OPTS+=(-k)

FAIL=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=1; }
warn() { echo "  ⚠️  $1"; }

HTML_FILE=$(mktemp "${TMPDIR:-/tmp}/cmplz-verify.XXXXXX") || exit 2
trap 'rm -f "$HTML_FILE"' EXIT

RESP=$(curl "${CURL_OPTS[@]}" -L -o "$HTML_FILE" -w '%{http_code} %{url_effective}' "$URL")
CODE="${RESP%% *}"; FINAL="${RESP#* }"
[ -s "$HTML_FILE" ] || { echo "❌ No response from $URL (HTTP ${CODE:-000})"; exit 1; }

echo "== Complianz verify: $URL =="
if [ -n "$FINAL" ]; then
  if [ "$(printf '%s' "${FINAL#*://}" | sed 's:/*$::')" != "$(printf '%s' "${URL#*://}" | sed 's:/*$::')" ]; then
    warn "redirected to $FINAL (checked the final page; use the canonical URL)"
  elif [ "${URL%%://*}" = "https" ] && [ "${FINAL%%://*}" = "http" ]; then
    warn "redirected from https to http: $FINAL"
  fi
fi

# 1. front end 200
[ "$CODE" = "200" ] && pass "front end HTTP 200" || fail "front end HTTP $CODE"

# 2. Complianz scripts
grep -q 'complianz' "$HTML_FILE" && pass "Complianz scripts present" || fail "no Complianz scripts in the HTML"

# 3. banner container, position, mode
BANNER=$(grep -o 'cmplz-cookiebanner[^"]*' "$HTML_FILE" | head -2 | tr '\n' ' ')
if [ -n "$BANNER" ]; then
  pass "banner container: $BANNER"
  grep -q 'cmplz-bottom-right' "$HTML_FILE" && pass "position: bottom-right" || warn "position is not bottom-right"
  grep -Eq 'cmplz-(cookiebanner|header|message)-[0-9]+-optin|consenttype"?[[:space:]]*:[[:space:]]*"optin' "$HTML_FILE" && pass "mode: opt-in" || warn "no opt-in marker (an opt-out region, or a wizard never finished: gotcha #50)"
else
  fail "no cmplz-cookiebanner container"
fi

# 4. trackers blocked before consent: every occurrence is located by element span (a <script>
#    element including its body, a <link>, <iframe> or <img> tag, found in one left-to-right pass
#    like a browser) and classified; one live copy is enough to fail. Resource hints (dns-prefetch / preconnect) transfer nothing and are skipped.
#    Occurrences inside HTML comments are ignored and those inside <noscript> are counted as
#    no-JavaScript fallbacks (warning). Matches anywhere else (inline styles, text) are reported as
#    not classified, for the browser audit. On the Consent Mode v2 path Google tags load before consent
#    by design: leave gtm.js and gtag/js out of the tracker list there (golden-path.md section 3B).
#    (The heredoc stays outside $( ): bash 3.2 misparses quotes in a heredoc inside a substitution.)
read -r -d '' CLASSIFY <<'PY'
import re, sys
html = open(sys.argv[1], encoding='utf-8', errors='replace').read()
needle = sys.argv[2]
hint = re.compile(r"""rel\s*=\s*["']?(?:dns-prefetch|preconnect)""", re.I)
OPEN = r"""(?:"[^"]*"|'[^']*'|[^'">])*>"""
# one left-to-right pass: whichever construct starts first owns its span, so a comment inside a
# script body and a script inside a comment are both read the way a browser reads them
MEDIA = 'link|iframe|img|embed|object|source|video|audio'
token = re.compile(r'<!--.*?(?:-->|$)'
                   r'|<(script|style|noscript)\b' + OPEN + r'.*?(?:</\1\s*>|$)'
                   r'|<(?:' + MEDIA + r')\b' + OPEN +
                   r'|<[a-zA-Z][\w:-]*\b' + OPEN, re.S | re.I)
spans = []
for m in token.finditer(html):
    s = m.group(0)
    if s.startswith('<!--'):
        spans.append((m.start(), m.end(), 'comment', ''))
        continue
    kind = re.match(r'<([\w:-]+)', s).group(1).lower()
    head = re.match(r'<[\w:-]+\b' + OPEN, s, re.S).group(0)
    spans.append((m.start(), m.end(), kind, head))
MEDIA_KINDS = set(MEDIA.split('|'))
start, saw_hint, blocked_n, other, fallback, active = 0, False, 0, 0, 0, []
while True:
    p = html.find(needle, start)
    if p < 0:
        break
    start = p + len(needle)
    sp = next((s for s in spans if s[0] <= p < s[1]), None)
    kind = sp[2] if sp else None
    if kind == 'comment':
        continue
    if kind == 'noscript':
        fallback += 1
        continue
    if kind == 'script' and re.search(r'(?<![\w-])type\s*=\s*["\']?(?:application/(?:ld\+)?json|text/(?:x-)?template|importmap)', sp[3], re.I):
        other += 1          # data, not code: nothing runs from here
        continue
    if kind == 'script':
        blocked = bool(re.search(r'(?<![\w-])type\s*=\s*["\']?text/plain', sp[3], re.I))
    elif kind in MEDIA_KINDS:
        if kind == 'link' and hint.search(sp[3]):
            saw_hint = True
            continue
        # the attribute that carries the URL decides. Only Complianz's own attributes mean "held back
        # until consent": data-src-cmplz / data-cmplz-src, or data-href on a tag Complianz marked with
        # data-category / data-service. Any other data-* (data-src, data-lazy-src, data-pmdelayedstyle)
        # belongs to a lazy-loader or optimizer and loads on scroll or interaction WITHOUT consent.
        attr = re.findall(r"""([\w:-]+)\s*=\s*(?:"[^"]*|'[^']*|[^\s"'>]*)$""", html[sp[0]:p])
        name = attr[-1].lower() if attr else ''
        low = sp[3].lower()
        blocked = name in ('data-src-cmplz', 'data-cmplz-src') or (
            name == 'data-href' and ('data-category' in low or 'data-service' in low))
        if not blocked and name.startswith('data-'):
            active.append(f'held back by a lazy-loader or optimizer ({name}), not by consent: '
                          + ' '.join(sp[3].split())[:90])
            continue
    elif kind is None or kind == 'style':
        other += 1
        continue
    else:
        other += 1
        continue
    if blocked:
        blocked_n += 1
    else:
        active.append(' '.join(sp[3].split())[:120])
note = f"; {fallback} in <noscript>" if fallback else ""
if active:
    print(f"ACTIVE\t{len(active)} live, {blocked_n} blocked{note}; first live tag: {active[0]}")
elif other:
    print(f"UNKNOWN\t{other} occurrence(s) outside script, link or media tags, {blocked_n} blocked{note}")
elif blocked_n:
    print(f"BLOCKED\t{blocked_n} occurrence(s){note}")
elif fallback:
    print(f"NOSCRIPT\t{fallback} occurrence(s), all inside <noscript>")
else:
    print("HINT_ONLY" if saw_hint else "ABSENT")
PY
TAB=$(printf '\t')
UNCLASSIFIED=0
for T in "${TRACKERS[@]}"; do
  RES=$(python3 -I -c "$CLASSIFY" "$HTML_FILE" "$T")
  KIND="${RES%%"$TAB"*}"; INFO=""; [ "$KIND" != "$RES" ] && INFO="${RES#*"$TAB"}"
  case "$KIND" in
    BLOCKED)   pass "tracker blocked until consent: $T ($INFO)" ;;
    ABSENT)    warn "tracker not present in the HTML: $T" ;;
    HINT_ONLY) warn "only resource hints (dns-prefetch / preconnect) for: $T (no transfer; confirm with a network audit)" ;;
    NOSCRIPT)  warn "only in <noscript> fallbacks: $T ($INFO; runs only without JavaScript, not blocked by Complianz)" ;;
    UNKNOWN)   warn "not classified: $T ($INFO; inline style, CSS or text? check with the browser network audit)"; UNCLASSIFIED=1 ;;
    ACTIVE)    fail "tracker ACTIVE before consent: $T ($INFO)" ;;
    *)         fail "could not classify tracker: $T" ;;
  esac
done

# 5. policy links (informational): same-site hrefs whose path contains a common policy slug must
#    answer 200 (links to other sites are listed, not requested)
ORIGIN=$(printf '%s' "${FINAL:-$URL}" | sed -E 's#^(https?://[^/]+).*#\1#')
SLUGS='privacy-policy|cookie-policy|privacy-statement|cookie-statement|privacy|cookies|datenschutz|datenschutzerklaerung|cookie-richtlinie|politique-de-confidentialite|politique-cookies|politica-de-privacidad|politica-de-cookies|privacybeleid|cookiebeleid|polityka-prywatnosci|polityka-cookies'
grep -oE "href=[\"'][^\"']*/($SLUGS)/?([?#][^\"']*)?[\"']" "$HTML_FILE" \
  | sed -E "s/^href=[\"']//; s/[\"']\$//" | sort -u | head -6 | while read -r LINK; do
  case "$LINK" in
    //*) LINK="https:$LINK" ;;
    /*) LINK="$ORIGIN$LINK" ;;
    http://*|https://*) ;;
    *) continue ;;
  esac
  LINK="${LINK//&amp;/&}"
  case "$LINK" in
    "$ORIGIN"/*|"$ORIGIN") ;;
    *) warn "policy link on another site (not checked): $LINK"; continue ;;
  esac
  # follow redirects by hand, and only while they stay on the same site
  HOP="$LINK"; PCODE=000
  for _ in 1 2 3 4 5; do
    RES=$(curl "${CURL_OPTS[@]}" -o /dev/null -w '%{http_code} %{redirect_url}' "$HOP")
    PCODE="${RES%% *}"; NEXT="${RES#* }"
    case "$PCODE" in 30[1278]) ;; *) break ;; esac
    case "$NEXT" in "$ORIGIN"/*) HOP="$NEXT" ;; *) PCODE="$PCODE to another site"; break ;; esac
  done
  [ "$PCODE" = "200" ] && pass "policy link → 200: $LINK" || warn "policy link → $PCODE: $LINK"
done

# 6. noscript fallbacks (informational)
python3 -I -c "import re,sys; h=re.sub(r'<!--.*?-->', '', open(sys.argv[1],encoding='utf-8',errors='replace').read(), flags=re.S); sys.exit(0 if any('googletagmanager' in m.group(0).lower() for m in re.finditer(r'<noscript\b.*?</noscript\s*>', h, re.S | re.I)) else 1)" "$HTML_FILE" && warn "noscript GTM fallback present (not blocked, small margin)"

if [ $FAIL -ne 0 ]; then RESULT='FAIL ❌'
elif [ $UNCLASSIFIED -eq 1 ]; then RESULT='PASS ✅ (with unclassified occurrences: confirm in the browser)'
else RESULT='PASS ✅'; fi
echo "== Result: $RESULT =="
exit $FAIL
