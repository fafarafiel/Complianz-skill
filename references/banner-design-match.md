# Matching the banner to the site's design (mandatory part of golden-path section 2)

> Matching only the color of the Accept button is NOT enough. A banner whose font and button shape
> differ from the site reads as a foreign widget, and that was exactly why a first banner was
> rejected in review. This procedure is part of EVERY deployment, not an option.

## Principle

The banner should look like a NATIVE element of the site: the same **font**, **weight**, **letter
case (uppercase?)**, **radius (pill vs square)**, **button style** (solid primary + ghost
secondary) and **brand colors**.

## Step 1: design probe (ALWAYS, pre-flight row 7 in golden-path section 0)

```bash
bash scripts/run-design-probe.sh https://example.com/ --headless
```

The probe clears cookies to see the site as a first-time visitor, so it runs in its own dev-browser
instance (`cmplz-probe`) and refuses `--connect`; your logged-in wp-admin page is not affected.

Returns: `siteButtons[]` (computed styles of the site's CTAs), `primaryButton` (the most common
style), `mainFontFamily`, `mainFontRendersPreConsent`, `fontChecks[]` (the fonts the banner may copy,
body text and every distinct button font, with whether each renders here and whether the page loaded
it as a web font), `blockedGoogleFontFamilies[]`, `fontsBlockedPreConsent`,
`externalFontRequestsPreConsent[]`, `banner{}` (current banner buttons, if present), and `fontNote`
when one of those fonts does not render but is not a blocked Google family (for example a font missing
on the probing machine: check its source by hand). `fontsBlockedPreConsent` is true when a font the
banner may copy is one of the blocked Google families and the page did not load it as a web font
(a copy installed on your own machine does not hide the problem).

Build the target map from it. Example: font `Nunito` 600 uppercase, radius **6px**, primary = solid
`#1D4ED8` with white text, secondary = outline. Decision: Accept = SOLID `#1D4ED8` with white text
(strong CTA), Deny / Preferences = GHOST white with `#1D4ED8` border and text, same size as Accept.
That keeps the visual hierarchy of the site.

## Step 2: font before consent (CRITICAL, easy to miss)

The flag describes the page as it is NOW. Before the wizard finishes (or before Google Fonts blocking
is switched on) nothing is blocked yet, so the flag is false by construction: re-run the probe after
the wizard, or in pre-flight treat a Google-hosted body or button font as blocked (pre-flight row 4).

If `fontsBlockedPreConsent: true`, a font the banner copies (body text or buttons) is a **Google Font
that Complianz blocks before consent** (`data-href`). The banner is shown BEFORE consent, so it renders a fallback
(Times / Arial), NOT the brand font. That breaks the banner's look (and the whole page before
consent, see the note at the end).

Fix: **self-host the font for the banner only, as base64** (same origin = loads before consent, ZERO
external calls = still GDPR friendly, since a local font needs no consent):

```bash
python3 scripts/font-to-base64.py "Nunito" "300 700" NunitoBanner --subsets latin,latin-ext > fontface.css
```

Use a UNIQUE `@font-face` name (for example `NunitoBanner`) so it does not collide with the blocked
external family of the same name. A weight range needs a variable font (one file covers the range);
for a static font the script embeds the first weight only and says so, so ask for the weight the
buttons use. Add `latin-ext` whenever the banner text uses letters outside basic latin (Polish, Czech,
Turkish, Romanian and many more).
Most Google Fonts are licensed under the SIL Open Font License, which allows embedding; check the
license of the font you use.

If `fontsBlockedPreConsent: false` (local or system font, or fonts not blocked), skip base64; a
`font-family` declaration is enough.

## Step 3: build the banner CSS

Template (replace the values with your probe results; `FONTFACE` = the output of step 2, or drop
that line):

```css
FONTFACE
.cmplz-cookiebanner,.cmplz-cookiebanner *{font-family:'NunitoBanner','Nunito',sans-serif !important;}
.cmplz-cookiebanner .cmplz-title{font-weight:700 !important;}
.cmplz-cookiebanner .cmplz-btn{
  font-family:'NunitoBanner','Nunito',sans-serif !important;
  font-weight:600 !important;
  font-size:15px !important;
  letter-spacing:.04em !important;
  text-transform:uppercase !important;
  border-radius:6px !important;
  padding:12px 28px !important;
  border:2px solid #1D4ED8 !important;
  line-height:1.2 !important;
  transition:background-color .15s,color .15s !important;
  cursor:pointer !important;}
.cmplz-cookiebanner .cmplz-btn.cmplz-accept{background:#1D4ED8 !important;color:#fff !important;border-color:#1D4ED8 !important;}
.cmplz-cookiebanner .cmplz-btn.cmplz-deny,.cmplz-cookiebanner .cmplz-btn.cmplz-view-preferences,
.cmplz-cookiebanner .cmplz-btn.cmplz-save-preferences,.cmplz-cookiebanner .cmplz-btn.cmplz-manage-options{
  background:#fff !important;color:#1D4ED8 !important;border-color:#1D4ED8 !important;}
.cmplz-cookiebanner .cmplz-btn:focus{outline:none !important;box-shadow:none !important;}
.cmplz-cookiebanner .cmplz-btn.cmplz-accept:hover{background:#1E3A8A !important;border-color:#1E3A8A !important;}
.cmplz-cookiebanner .cmplz-btn.cmplz-deny:hover,.cmplz-cookiebanner .cmplz-btn.cmplz-view-preferences:hover,
.cmplz-cookiebanner .cmplz-btn.cmplz-save-preferences:hover,.cmplz-cookiebanner .cmplz-btn.cmplz-manage-options:hover{
  background:#1D4ED8 !important;color:#fff !important;}
.cmplz-cookiebanner .cmplz-btn:focus-visible{outline:2px solid #1D4ED8 !important;outline-offset:2px !important;}
.cmplz-cookiebanner .cmplz-btn:active{opacity:.9 !important;}
.cmplz-cookiebanner .cmplz-close:focus,.cmplz-cookiebanner .cmplz-close:focus-visible{
  box-shadow:none !important;outline:2px solid #1D4ED8 !important;outline-offset:2px !important;}
.cmplz-cookiebanner a.cmplz-link{color:#1D4ED8 !important;font-weight:600 !important;}
```

Notes:
- Complianz button classes: `.cmplz-accept`, `.cmplz-deny`, `.cmplz-view-preferences`,
  `.cmplz-save-preferences`, `.cmplz-manage-options`. Title: `.cmplz-title`. Links: `a.cmplz-link`.
  Close icon: `.cmplz-close`.
- Cover every interactive state, not only `:hover`: `:focus`, `:hover`, `:focus-visible`,
  `:active`, in that source order. A mouse click leaves focus on the button, so a rule that only
  covers `:hover` leaves the theme's focus color on screen after a click (#21 for the close icon).
- States change only `color`, `background-color`, `outline`, `opacity`; never `padding`, `border`
  width or `margin` (the layout would jump).
- No `<` or `>` anywhere in the CSS (no child combinators): sanitizing filters eat them on save
  (#18). Write `A B` instead of `A > B`. `apply-banner-css.py` refuses CSS that contains them.
- Keep Deny the same size as Accept (equal ease of refusal).

## Step 4: inject the CSS through the RELIABLE path (NOT the Complianz Custom CSS editor)

**The Complianz "Custom CSS" editor (ACE) did not work for this on 7.6.0.** The value persisted in the
config and the "Use custom CSS" toggle switched on, but the rules never reached the front end (#16).

**Use the WordPress Customizer "Additional CSS"** (core, output guaranteed in
`<style id="wp-custom-css">`):

```bash
( umask 077; CMPLZ_URL=https://example.com/ python3 scripts/apply-banner-css.py banner.css > apply.js )
dev-browser --timeout 120 < apply.js
rm apply.js
```

The generated script: logs in only when the dev-browser profile is not logged in yet and
`CMPLZ_USER` / `CMPLZ_PASS` were provided (otherwise it stops with `NOT_LOGGED_IN`; log in once in a
headed dev-browser page as shown in the README, or pass the variables), auto-detects the `custom_css[<theme>]` setting id
(theme-namespaced, which is why `wp.customize('custom_css')` returns `undefined`, #17), saves the
current Additional CSS to `~/.dev-browser/tmp/` and stops with `PENDING_CHANGES` if the Customizer holds
other unpublished changes, sets the value
through `wp.customize(id).set()` (bypasses the CodeMirror sync), keeps an idempotent block between
`/* --- CMPLZ BANNER CSS START --- */` markers (the rest of the site's CSS is untouched), publishes
(`#save`), and then loads the front end and reports how many `cmplz` rules actually landed in
`#wp-custom-css` plus the `/*` vs `*/` balance, failing with `FRONT_CHECK_FAILED` when the rules did
not land. It accepts only `https://` URLs (`CMPLZ_ALLOW_HTTP=1` for a local test site). If you passed
credentials, `apply.js` contains them: delete it afterwards.

Fallbacks when the Customizer is unavailable (block themes keep Additional CSS in Site Editor >
Styles): a WPCode CSS snippet, or a mu-plugin on `wp_head` uploaded over SFTP (`php -l` first; a parse
error takes the whole site down, #45).

## Step 5: verify (with evidence)

dev-browser as an anonymous visitor, fresh `?cb=`:
- the base64 family really renders (compare the width against `monospace`; do NOT trust
  `document.fonts.check`, it returns true for fonts that never loaded)
- computed `.cmplz-accept` / `.cmplz-deny`: font, weight, radius, background, color, border match the
  map from step 1; Accept and Deny have the same size
- **zero external requests to `fonts.googleapis` / `fonts.gstatic` before consent** (base64 is same
  origin), checked after scrolling to the bottom and moving the mouse, so fonts held back by a
  delayed-style optimizer show up too
- E2E still works (accept → allow + fonts load, deny → deny). Screenshot of the banner (clip
  `.cmplz-cookiebanner`).

## Note about the rest of the page (tell the site owner)

Blocking Google Fonts degrades the typography of the WHOLE site for every visitor BEFORE consent (a
fallback until "Accept"). The base64 font from this procedure fixes only the BANNER. The real
site-wide fix is a true self-host of the fonts (Elementor's local Google Fonts option, a plugin such
as OMGF, or self-hosting in the theme). The Complianz "self-host Google Fonts" option (observed on
7.6.0) did NOT fetch fonts enqueued by Elementor or the theme; it left the external `href` live without consent, which
is a privacy REGRESSION worse than blocking (#20). A brand font site-wide before consent is a
separate task, outside the scope of the banner.
