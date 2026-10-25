---
name: complianz-deploy
description: >
  Deploy, configure, style and verify the Complianz GDPR cookie consent banner (Premium or Free)
  on a WordPress site: pre-flight checks, the React admin wizard, a banner matched to the site's
  design, blocking of hardcoded trackers (GTM, Meta Pixel, Google Fonts, embeds), Google Consent
  Mode v2, WPML, and end-to-end verification with evidence. Use when the user says: "deploy
  Complianz", "set up Complianz for [site]", "cookie banner for [site]", "consent banner",
  "GDPR cookie banner", "configure Complianz", "run the Complianz wizard", "verify Complianz on
  [URL]", "why is the Complianz banner not showing", "Complianz does not save settings",
  "Consent Mode v2 with Complianz", "Google asked us to fix our consent banner" (tolerate typos:
  complianz / compliance / komplianz). Do NOT use for other consent plugins (CookieYes, Cookiebot,
  Real Cookie Banner, Moove GDPR) unless the task is a migration TO Complianz. Never generates
  legal documents.
---

# Complianz Deploy: cookie banner playbook

**Goal:** a complete Complianz deployment in 30 to 60 minutes instead of a multi-hour session.
Every step below exists because skipping it cost hours on a real site. Do not skip the
pre-flight and do not trust a save until you have read it back.

## Workflow (always in this order)

1. **Pre-flight** → `references/golden-path.md` section 0. Ten checks BEFORE you open the
   wizard. Output: a decision table the user confirms with ONE batched question (including the
   visitor regions: EU only, or also the US or other regions).
2. **Backup** → dump the options table and the `cmplz_*` tables (WP-CLI over SSH, or an export;
   command in golden-path section 0).
3. **Wizard** → `references/golden-path.md` section 1 (screen order and what to pick).
4. **Banner styling, matched to the site's design (mandatory)** → section 2 and
   `references/banner-design-match.md`. Pipeline: `scripts/run-design-probe.sh` (the site's
   button tokens: font, weight, uppercase, radius or pill, colors, solid vs ghost) → if the body or
   button font is a Google Font that Complianz blocks before consent: `scripts/font-to-base64.py`
   (self-hosted base64 that renders pre-consent) → CSS from the template →
   `scripts/apply-banner-css.py` + dev-browser (inject through **Customizer
   `custom_css[<theme>]`**, NOT the Complianz Custom CSS editor, which on 7.6.0 did not reach the
   front end; gotchas #16, #17). Matching only the Accept color is not enough: a banner with the
   wrong font or button shape reads as foreign and gets rejected in review.
5. **Block hardcoded trackers** → section 3 (Script Center; remember the GLOBAL Save). Audit the
   GTM container first: a container with ad tags goes under Marketing, not Statistics (#23).
   - **5b. Consent Mode v2** (the site runs Google Ads, including GA4 linked to Ads, or Google asked the owner to fix the
     consent banner) → section 3B. The Consent Mode field exists ONLY (observed on 7.5.2) when "Complianz adds
     GTM" = Yes (gotcha #37), so ownership of the GTM snippet moves to Complianz and any
     hardcoded copy (Elementor Custom Code, WPCode, theme, including the **body/noscript**
     part) is switched off reversibly. Consent Mode covers Google tags only: inline Meta Pixel is
     still blocked by Complianz, but non-Google tags INSIDE the GTM container fire before consent
     unless the container is audited (Complianz consent-event triggers; GTM consent settings only
     in addition, section 3B).
6. **End-to-end verification** → section 4 + `bash scripts/verify.sh <URL> [tracker...]` + a
   browser test (accept and deny) + a screenshot for the reviewer. These are opt-in checks; visitors
   in an opt-out region (for example the US) are verified with the US checklist in section 1.
7. **Multilingual (WPML)?** → section 5 (fix the string source language, then translate).

## House rules (defaults, change them to match your own policy)

- **Never generate legal documents.** Link the site's existing policy pages ("Existing page").
  Do NOT click "Update pages". Elementor Legal Hub = No. Do not edit the content of policy pages
  without explicit approval from the site owner. The only exceptions, each on the owner's explicit
  request: the Complianz-generated cookie policy, and for a US region the Complianz-generated opt-out
  page (golden-path section 1).
- **Hardcoded tags stay in the code.** By default Complianz is not asked to add a GTM snippet: a
  hardcoded GTM is blocked before consent through Script Center, and an inline Meta Pixel is blocked
  by Complianz natively. The exception is the Consent Mode v2 path, where Complianz owns the GTM
  snippet and the hardcoded copy is switched to Draft.
- **Banner position: bottom-right box.**
- **Banner and button radius = the site's buttons** (check in pre-flight; often 0px).
- **Do NOT click "Start" on the website scan / cookiedatabase.org sync.** It registers the domain
  with an external Complianz service and needs an e-mail confirmation; that is the site owner's
  decision. The scan is not needed for the banner to work (service auto-detection works without it).
- When scope is unclear: one batched question, not a series of interruptions.

## Technical traps (short list; full list in `references/gotchas.md`)

| Symptom | Cause → fix |
|---|---|
| Saves "succeed" but nothing changes / banner never shows | Stale REST nonce in the SPA → hard reload `admin.php?page=complianz&fresh=<ts>#...` before every batch of saves; read the `fields/set` response (#1) |
| Clicking a checkbox or radio does nothing | React (Radix UI), no `<input>` → Playwright locator (trusted click), read state from `aria-checked`; if stubborn, DOM click via evaluate (#2) |
| `.fill()` does not save the value | React state → native value setter + dispatch `input` / `change` (#3) |
| Script Center entry has no effect | You saved only the entry; click the **global Save** of the page too (#5) |
| Banner text in the wrong language | The wizard inherits the ADMIN's locale → see WPML handling (#9, #39) |
| Selector `#0_url` throws | ID starts with a digit → `[id="0_url"]` (#6) |
| "Save and continue" locator times out | It is an `<a class="button-primary">`, not a `<button>` (#4) |
| dev-browser script killed after 30 s | Default timeout; pass `--timeout 120` or split UI loops into chunks of 6 or fewer (#52) |
| dev-browser page jumps to another site | Do not use the shared page `main`; use a dedicated page name per site (#51) |
| Banner CSS "saved", zero rules on the front end | A marker containing `<` was eaten by a sanitizing filter (#18). No `<` or `>` in injected text; verify by counting rules in `document.styleSheets`, not by the save response |
| No "Google Consent Mode V2" field in the wizard | Observed on 7.5.2: appears only when "Complianz adds GTM" = Yes; it is not on the Integrations page (#37) |
| Is Consent Mode working? | Google's method (Tag Assistant): the earliest Consent event sets `ad_storage`, `analytics_storage`, `ad_user_data`, `ad_personalization` = denied, the update after Accept = granted. `gcs` on `g/collect` / `ccm/collect` shows only the storage pair (`G100` / `G111`), so it cannot prove v2 alone (#38). GTM loading before consent is CORRECT under Consent Mode; for Google tags check signals and cookies, but any request from a non-Google tag before consent is still a violation |
| Complianz Custom CSS does not reach the front end | Observed on 7.6.0: stored but not output (#16) → use **Customizer `custom_css[<theme>]`** via `scripts/apply-banner-css.py` (#17); fallbacks: WPCode CSS snippet, or a mu-plugin on `wp_head` (`php -l` first, #45) |
| Banner renders in a fallback font before consent | The body or button font is a blocked Google Font → base64 self-host for the banner (`scripts/font-to-base64.py`, #20). `document.fonts.check` gives false positives; measure width against monospace |

## Scripts

- `scripts/verify.sh <URL> [tracker-substring ...]`: curl-based check. Front 200, Complianz
  scripts, banner container and position, trackers blocked before consent (`text/plain` /
  `data-href`), policy links. Default trackers: `googletagmanager.com/gtm.js`,
  `googletagmanager.com/gtag/js`, `fbq('init'`, `connect.facebook.net`, `fonts.googleapis`. Resource hints (`dns-prefetch` / `preconnect`) are reported as hints, not
  as active trackers; every occurrence is checked and the first live tag is printed. On the
  Consent Mode path leave `gtm.js` and `gtag/js` out of the list (Google tags load before consent there). HTML layer only; confirm with a network audit in
  the browser (#41).
- `scripts/run-design-probe.sh <URL> [dev-browser flags]`: runs `scripts/design-probe.js` in its
  own dev-browser instance (`cmplz-probe`; it clears cookies there and refuses `--connect`). Returns the site's button tokens and detects fonts blocked before consent
  (`fontsBlockedPreConsent`). Input for the design match (section 2, #16, #17, #20).
- `scripts/font-to-base64.py <family> <weight|range> [css-name] [--subsets latin,latin-ext] [--json]`:
  Google Font → `@font-face` in base64 (same origin, renders before consent, no external call). A
  range needs a variable font; add `latin-ext` for most European languages.
- `scripts/apply-banner-css.py <css-file>` (env `CMPLZ_URL` with https, optional `CMPLZ_USER` /
  `CMPLZ_PASS`): generates a dev-browser script that injects the CSS through Customizer
  `custom_css[<theme>]` (auto-detects the setting id, idempotent marker block, publishes) and
  then reads the front end back; it fails with `FRONT_CHECK_FAILED` when the rules did not land.
  Block themes have no Customizer CSS: use Site Editor > Styles > Additional CSS or WPCode.
- Full styling procedure: `references/banner-design-match.md`.

## Provenance

Created by Fafarafiel, iD4.pl (https://id4.pl). Distilled from ten production WordPress deployments
(June to October 2026, Complianz 7.5.2 to 7.6.6, EU sites including multilingual WPML setups).
`references/gotchas.md` is the knowledge base; add every new trap there after each deployment.
