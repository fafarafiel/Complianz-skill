# Golden path: deploying Complianz step by step

> The order matters: the pre-flight removes about 80% of the detours seen in real deployments.
> Admin labels are quoted from the English UI of Complianz 7.5 / 7.6 and may differ slightly in
> your version or locale. `#N` refers to `gotchas.md`.

## Section 0: PRE-FLIGHT (before you open the wizard; about 10 minutes with curl / REST / WP-CLI)

Collect EVERYTHING below before clicking anything in the panel. Present the result to the site
owner as a table plus at most ONE batched question (for example: visitor regions, blocking vs
Consent Mode, banner position, Records of Consent).

| # | Check | How | Why |
|---|-------|-----|-----|
| 1 | Complianz version, Free vs Premium, updates | `wp plugin list \| grep -i complianz`, or authenticated REST (application password) `GET /wp-json/wp/v2/plugins?search=complianz` | Older versions have a different UI; update BEFORE the wizard. Free + Premium both active = trouble (#49) |
| 2 | Policy pages exist? | `curl -I` on the policy URLs | "Existing page" mode needs real pages; their content is NOT touched |
| 3 | Tracking stack on the front end | `curl` the homepage, shop and cart, then grep: `GTM-`, `fbq(`, `connect.facebook`, `gtag`, `clarity`, `matomo`, `snap.licdn`, `<noscript>`. Also `wp post list --post_type=elementor_snippet --post_status=any --fields=ID,post_title,post_status` and a runtime network audit (#29) | Drives the Consent answers and what Script Center must block. No tracking at all → Statistics = No |
| 4 | Google Fonts: where do the body and button fonts come from? | grep `fonts.googleapis` + the theme's font source (Elementor may already serve them locally, `elementor_local_google_fonts=1`); row 7 checks both fonts | Fonts local → blocking Google Fonts has no visual risk. Body or button font from Google → banner needs a base64 font (#20) |
| 5 | Multilingual (WPML / Polylang)? | `/wp-json/` namespaces (`pll/v1`, WPML) | Yes → section 5. Admin locale different from the site language is a trap (#9) |
| 6 | WAF / REST access | test `/wp-json/` vs `?rest_route=`; Basic Auth | Some hosts answer 406 on `/wp-json/` + Basic Auth (#44). Agree on an emergency file channel (SFTP / FTPS before a file manager plugin) |
| 7 | **Design tokens of the site's buttons** | `bash scripts/run-design-probe.sh https://example.com/ --headless` | Full banner match: font family, weight, **uppercase?**, **radius (pill?)**, padding, colors, solid vs ghost, plus `fontsBlockedPreConsent` (meaningful only after the wizard, see `banner-design-match.md` step 2). Matching only the Accept color is NOT enough. See `banner-design-match.md` |
| 8 | Admin locale vs site language | `wp eval 'echo get_locale();'` + the admin user's locale | Admin in one language on a site in another = banner texts in the admin's language (#9) |
| 9 | Work channels | dev-browser login OK? SSH / WP-CLI? SFTP / FTPS? | The panel is a React SPA: drive the UI with dev-browser on a DEDICATED page (#51); use WP-CLI for backups and reading options |
| 10 | Is the admin session stable? | watch for `wp-auth-check-wrap` / logouts | Sessions dying after minutes → atomic scripts that log in at the start (#47) |

Also check `GET /wp-json/complianz/v1/banner` from an IP inside the regions the site targets (or the
wizard state through WP-CLI): `consenttype: "other"` and `documents: []` mean the plugin is installed
but never configured (#50). Read from outside the configured regions, the same answer can simply mean
"no banner for this region".

**Backup before you start** (`--tables` takes a comma-separated list and does not expand wildcards,
so let `wp db tables` expand them):

```bash
P=$(wp db prefix)
wp db export ~/backup-pre-complianz-$(date +%Y%m%d-%H%M).sql \
  --tables="$(wp db tables "${P}options" "${P}cmplz_*" --all-tables-with-prefix --format=csv)"
```

A few MB and about a minute; it rolls back the whole configuration if needed. The dump contains
site options: download it, then delete it from the server.

## Section 1: WIZARD (screen order and what to pick)

Open `admin.php?page=complianz&fresh=<timestamp>#wizard`. **The cache buster gives you a fresh
nonce.** Hard reload with a new `fresh=` after EVERY return to the panel and about every 10
minutes. Without it saves come back `403 rest_cookie_invalid_nonce` and do NOT persist (#1).
Symptom: `consenttype: other`, banner never shows.

| Screen | Choice | Notes |
|-------|-------|-------|
| Visitors (regions) | **The regions the site's visitors come from** (part of the pre-flight question): EU (GDPR) for EU sites; the UK is its own region (check how your version treats Switzerland); add the US or other regions when visitors come from there (several regions at once need Premium geo-IP; on Free you can select only one region, so with EU visitors keep the EU opt-in model), where Complianz applies that region's model (in the US typically an opt-out banner and GPC). The field notes in this skill come from EU-only setups. "Banner in other regions = none" only when no visitors come from elsewhere; region-specific sub-questions (for example Germany/Austria, Spain) = per site; user accounts / login = Yes on WooCommerce | Click = `button[role=checkbox]`, read state from `aria-checked`. An UNSAVED region = no banner for those visitors! |
| Documents | Cookie policy + Privacy statement = **"Existing page"** → react-select (`react-select-N-input`, type 2+ characters, pick an option). Imprint / Disclaimer = None | NEVER "Generated by Complianz". **ONE policy page: point ONLY Cookie policy to it and set Privacy statement = None** (Cookie policy has no None option; Privacy statement does). Pointing BOTH to the same page renders the same link twice on the banner (#13) |
| Website information | Country = the site owner's country | Usually pre-filled (Radix combobox, #10) |
| Security & Consent | Records of Consent: Yes for e-commerce, lead generation and any Google Ads / Consent Mode site; No for minimal sites. Data requests: No on EU-only sites; per region and owner's decision otherwise. Do Not Track / GPC: **Yes whenever the US is among the visitor regions** (in recent versions the option also honors Global Privacy Control, which California and several other states require you to respect); on EU-only sites it is not legally required: No when there is tracking (it would hide the banner from DNT visitors), Yes when there is none or as the privacy-friendlier choice | Per site; include it in the pre-flight question |
| **Website scan** | **SKIP** ("Continue"). Do NOT click "Start" (#8) | Service auto-detection (`cmplz_detected_*`) works without the scan |
| Consent → Statistics | From pre-flight row 3: GTM → "Yes, with Google Tag Manager"; GA4 inline → "Yes, with Google Analytics"; tracking coming later → "Yes, but not with any of the above services" (#11); none → "No". Google sub-checkboxes empty = stricter (statistics need consent) | |
| Statistics configuration | **"Should Complianz add GTM / GA?" = No** when the snippet is already in the code (otherwise it loads twice). Consent Mode v2 only on the section 3B path (#37) | |
| Services | Google Fonts per pre-flight row 4; "advertising scripts" = Yes with Meta Pixel / Ads; framework = none (TCF only for AdSense / Ad Manager); comments = Yes with WooCommerce reviews; social per detection | |
| Plugins | Integrations automatic; **Elementor Legal Hub = No** | |
| Cookie descriptions (cookiedatabase.org) | **SKIP** (needs the scan service, like the website scan) | |
| Documents (create) | Generate nothing; **do NOT click "Update pages"** (it changes the titles of the site's pages!) | |
| Link to menu | Keep the default (geo-IP redirect, no menu changes); do NOT pick "No, select a menu" (#12) | |
| **Finish** | Show the consent banner = **Yes**; cookie and script blocker = **Yes** → "Finish" | Both toggles start UNSET |

**When the US (or another non-EU region) is among the visitor regions.** The field notes behind this
skill come from EU-only sites, so treat this as a checklist, not tested settings:
- Complianz applies that region's model to those visitors (in the US typically an opt-out banner with
  an opt-out / "Do Not Sell or Share" style link instead of an opt-in banner). The opt-out page is the
  owner's decision, like any legal document here: an existing page with a working opt-out, or the page
  Complianz generates on the owner's explicit request. Have counsel confirm the texts.
- Do Not Track / GPC: answer **Yes** (see the Security & Consent row).
- Verification differs. Under the opt-out model trackers and cookies are present on load by design, so
  section 4's opt-in assertions (zero requests, cookie inventory) do not apply there. `verify.sh`
  reads the same HTML for every region and cannot judge the opt-out model; a tag it reports as ACTIVE
  is still a defect, because neither opting out nor GPC can stop it. Instead check, from a US IP: the opt-out link or control is
  visible; after opting out the tracker requests and cookies stop and the choice is remembered; a
  visitor sending GPC (`Sec-GPC: 1`, `navigator.globalPrivacyControl`) is treated as opted out. On an
  EU + US site run section 4 from an EU IP and this check from a US IP.
- Test from the region itself: with Premium geo-IP the banner differs per region, so use a proxy or VPN
  in that region, or read `region` and `consenttype` from
  `/wp-json/complianz/v1/banner?lang=xx&locale=xx_XX` called from there.

Exception, only on the site owner's explicit request: a cookie policy generated by Complianz at a
URL you control. Create the page first (slug of your choice, content
`[cmplz-document type="cookie-statement"]`), then link it as "Existing page". You get your own URL and
the generated cookie policy, with no surprise slug. The text is still the owner's legal document to
review.

## Section 2: BANNER (style)

> **A full match to the site's design is MANDATORY.** Complete procedure (probe → base64 font
> before consent → CSS template → injection through the Customizer → verification) in
> `banner-design-match.md`. Matching only the Accept color is NOT enough: font, letter case,
> radius (pill?) and the solid vs ghost style must match the site's own buttons.
>
> Pipeline: `scripts/run-design-probe.sh` (tokens) → if `fontsBlockedPreConsent`:
> `scripts/font-to-base64.py` (base64 self-host) → CSS from the template →
> `scripts/apply-banner-css.py` + dev-browser (injection through **Customizer
> `custom_css[<theme>]`**, NOT the Complianz Custom CSS editor, which on 7.6.0 did not reach the
> front end, #16).

Panel: Consent Banner (`#banner`), tabs General / Appearance / Colors / Text / Custom CSS.

1. **Appearance:** Position = "Bottom right" (usually the default). Radius: two groups of four
   number fields (banner top / right / bottom / left, buttons the same) → match the site (native
   setter + dispatch `input` / `change`, #3). Do NOT touch the font size field next to them.
2. **Colors** (react-color swatches in a Radix popover, #7; at most four to six swatches per
   script, #52):
   - General: background and border = the brand's dark color (or the site's light background) /
     text = high contrast / hyperlink = accent
   - Toggles: active background = accent, bullet white, inactive grey
   - Buttons: Accept = accent with contrasting text (check the AA badge in the panel);
     Deny / Settings = ghost (banner background, border and text in the text color)
3. **Text:** if the site language matches the admin locale, the default translations usually work
   out of the box; still read #14. Multilingual → section 5.
4. **Custom CSS:** inject through the Customizer, see `banner-design-match.md` step 4 and #17. The
   Complianz Custom CSS editor worked on 7.5.2 only with a fresh nonce and did not reach the front
   end on 7.6.0 (#16). Fallbacks when the Customizer is unavailable (for example block themes, where
   Additional CSS lives in Site Editor > Styles): WPCode CSS snippet, or a mu-plugin on `wp_head`
   uploaded over SFTP (`php -l` first, #45).
5. After each tab click **"Save"** and read the values back from the DOM.

**Equal ease of refusal:** EU regulators (the EDPB cookie banner taskforce and national data
protection authorities) expect refusing to be as easy as accepting. The safe reading: Deny on the same
layer, at the same level and the **same size** as Accept (measure with `getBoundingClientRect` on
desktop and mobile).

## Section 3: BLOCKING HARDCODED TRACKERS (Script Center)

Complianz does NOT block GTM under "your own implementation" (deliberate, #23). Inline Meta Pixel,
Google Fonts (when selected under Services with self-hosting off) and known tracker snippets in
Elementor Custom Code (GA4 gtag.js, Meta Pixel, LinkedIn Insight) are blocked natively (#24, #25); a
GTM snippet there is not. For GTM and
anything else that is not blocked:

1. `#integrations` → **Script Center** → section **"Block a script, iframe or plugin"** → its
   "Add new" (three sections have identical buttons; target index 1, #31; remove a stray entry with
   "Delete" in its expanded panel).
2. Entry: descriptive name; URL = a unique substring (for example `googletagmanager.com/gtm.js`,
   which also matches the inline loader); placeholder off. Category: Marketing for pixels and maps.
   For GTM, **audit the container first**: once the `gtm.js` entry is released, every tag inside
   fires on its own triggers. Analytics-only container → Statistics. Any ad, remarketing or social
   tag inside (Google Ads, Meta, LinkedIn, TikTok) → category Marketing for the `gtm.js` entry, or keep
   Statistics and move those tags to a `cmplz_event_marketing` trigger (the container owner's call).
   If you cannot see the container, use Marketing. Verify with statistics-only consent: no requests
   to ad endpoints.
3. "Save" the entry **AND the global "Save" of the page**. Without the global save the entry does
   nothing (#5).
4. Verify: `curl` the front end → the tag before the snippet has `type="text/plain" data-category=...`.

Also check what Complianz does not detect: Elementor Google Maps widget (#27), Vimeo background
video (#28), payment SDKs (#36) and WooCommerce order attribution, which sets `sbjs_*` cookies before
consent unless it is gated through the WP Consent API (#33): switch it off, or prove it waits.

`<noscript>` fallbacks (GTM iframe, Meta image pixel) are NOT blocked; mention it to the site owner
as a margin (#26).

## Section 3B: CONSENT MODE V2 (the site runs Google Ads, or Google asked for it)

**When to use this instead of section 3 (the routing rule):**
- any Google Ads on the site (an Ads tag in GTM, a gtag.js `AW-` tag, or GA4 linked to Google Ads for
  conversions), an e-mail from Google asking to fix the consent banner / consent mode, or planned
  conversion modeling → this section. Field-tested only with GTM (observed on 7.5.2, where the Consent
  Mode field appears only when Complianz adds GTM, #37; not re-run on 7.6.x): an Ads tag loaded through gtag.js without GTM
  goes into the GTM container that Complianz loads, unless your version offers Consent Mode on its
  Google Analytics path (not tested here; check that first);
- GA4 alone, through GTM or gtag.js, without Ads → the blocking path (section 3; an inline GA4 snippet
  is blocked natively, #25).

Complianz is on Google's list of certified CMPs, and Google tags read the consent signals by
themselves, so the Google tags in the container need no changes.

**Not a replacement for blocking:** Consent Mode covers Google tags only. On this path GTM loads
before consent, so:
- non-Google tags that are **hardcoded or inline** on the page (Meta Pixel `fbq`, LinkedIn Insight)
  are still blocked by Complianz natively;
- non-Google tags **inside the GTM container** (Meta, LinkedIn, TikTok, Hotjar and similar on an
  "All Pages" trigger) are NOT blocked by Complianz and would fire before consent. **Audit the
  container (mandatory):** fire each such tag on the Complianz consent events
  (`cmplz_event_marketing`, `cmplz_event_statistics`) instead of "All Pages". GTM's "Require
  additional consent" setting (for example `ad_storage`) is not relied on here on its own; use it, if at
  all, together with the event trigger.
  Also remove leftovers of a previous consent tool inside the container (consent-initialization
  tags, CMP templates or their triggers), which can override the Complianz signals. Changing the
  container is the container owner's decision; list the tags and agree on it. If the container cannot
  be changed, use the blocking path (section 3) with the `gtm.js` entry under Marketing instead; that
  path sends no Consent Mode signals at all, so it does not answer a Google request to fix consent
  mode.

### Prerequisite (#37)

Observed on 7.5.2: the field "Do you want to enable Google Consent Mode V2?" exists **only** in
`#wizard/statistics-configuration` and **only when** "Do you want Complianz to add Google Tag
Manager?" = **Yes**. The Integrations page has no such switch. In other words: **the GTM snippet must
belong to Complianz.**

When GTM is hardcoded (typically Elementor Pro → Custom Code, the theme, or WPCode):
1. Wizard: "Complianz adds GTM" = **Yes**, "Consent Mode V2" = **Yes**, GTM ID = `GTM-XXXXXXX`,
   "Tag Manager template" = **No** (the site has its own container; a site without one creates a
   container first), "force in header" = **No**.
2. Find EVERY place the old snippet is injected (`edit.php?post_type=elementor_snippet`, Code
   Snippets, WPCode, `header.php`), including the separate **body / noscript** entry.
3. Switch them off **reversibly** (status → Draft / toggle off); do NOT delete.
4. Verify on the front end: `GTM-XXXX` occurs **exactly once**. If the site was on the blocking path
   before, disable its Script Center entry for `googletagmanager.com/gtm.js` (and the global Save):
   otherwise GTM keeps waiting for consent and the Consent Mode pings never appear.
5. Audit the container for non-Google tags (see above) and verify in the browser that none of them
   sends a request before consent.

Order: finish the wizard first (the banner starts working), then switch off the duplicates right
away. The reverse order leaves the site without GTM for a while; this order leaves a brief duplicate,
and until it is switched off the hardcoded copy can run without the consent defaults, so keep that
window to minutes.

### What MUST happen before consent (do not "fix" it)

`gtag('consent','default')` with the four Google signals `ad_storage`, `analytics_storage`,
`ad_user_data`, `ad_personalization` `denied` (Complianz sets security and functionality storage to
granted) → GTM **loads** → Google tags send
cookieless pings. That is how Consent Mode works (whether cookieless pings before consent are
acceptable for your audience is a legal question; the blocking path is the conservative alternative). The `dataLayer` sequence on a
correct setup: `consent default` → `default_consent` → `cmplz_event_functional` → `consent update`
→ **only then** `gtm.js`.

Because the defaults and the update fire synchronously BEFORE `gtm.js`, **`wait_for_update` is not
needed**; its absence in the Complianz output is not a defect (unlike CMPs that apply consent
asynchronously).

### Verification (#38)

Google's own method is Tag Assistant ("Verify consent mode implementation"): the four signals in the
Consent events. The network and cookie columns are the same check from the browser side.

| Moment | Consent signals (Tag Assistant or `dataLayer`) | `gcs` on Google hits | Cookies |
|---|---|---|---|
| before consent | default: `ad_storage`, `analytics_storage`, `ad_user_data`, `ad_personalization` all **denied** | `G100` + `npa=1` | no `_ga`, `_gcl`, `_fbp` |
| after "Accept" | update: all four **granted** | `G111` | `_ga`, `_gcl`, `_fbp` present (for the tags that are installed) |
| after "Deny" | no granting update | no `G111` hits; cookieless `G100` pings may continue on later page loads (expected under Consent Mode; whether that is acceptable for your audience is a legal question) | only `cmplz_*` cookies, statistics and marketing `=deny`; no `_ga`, `_gcl`, `_fbp` |

`gcs` alone shows only the storage pair: confirm the two v2 signals in the Consent events (Tag
Assistant or the `dataLayer`) before you report Consent Mode v2 as working.

### Banner checks for a site running Google Ads

- "Deny" at the same level and **the same size** as "Accept" (`getBoundingClientRect`); equal ease of
  refusal is what EU regulators expect
- non-essential categories **unticked** by default (functional may be ticked); pre-ticked boxes are
  not valid consent under EU case law
- working **withdrawal** of consent after accepting (`.cmplz-manage-consent` visible); Google's EU User
  Consent Policy asks for clear instructions on revoking consent
- **Records of Consent = Yes**; Google's EU User Consent Policy asks you to keep records of consent

## Section 4: END-TO-END VERIFICATION (mandatory, with evidence)

1. **curl:** `bash scripts/verify.sh <URL> [trackers]`. On the Consent Mode v2 path pass your own
   tracker list without `googletagmanager.com/gtm.js` and `googletagmanager.com/gtag/js` (Google tags
   loading before consent is correct there), for example
   `bash scripts/verify.sh <URL> "fbq('init'" connect.facebook.net fonts.googleapis`.
2. **Browser** (dev-browser in its own headless instance with a fresh name per run, e.g.
   `dev-browser --headless --browser cmplz-e2e-$(date +%s)`, because an instance keeps its cookies
   between runs; so the test runs as an anonymous visitor and clearing cookies does not log out your
   admin page; #38 measurement trap. These instances pile up: `dev-browser browsers` lists them and
   `dev-browser stop` closes every instance, including the logged-in admin one. These assertions are
   for the opt-in model; for US opt-out visitors see the US checklist in section 1):
   - on load: banner visible (class `cmplz-bottom-right`, NOT `cmplz-hidden`, #40), computed
     colors and fonts as designed, texts in the site's language; **zero requests** to trackers
     (`page.on('request')` listener). Before asserting zero requests, scroll to the bottom of the page, wait a moment and move the mouse (do not click the banner): lazy-loaded iframes and "delay JS" optimizers load only then. Consent Mode path: a `consent` `default` with all four signals
     denied comes first (#38); `gtm.js` and cookieless `gcs=G100` pings are expected; zero requests to
     non-Google trackers; no `_ga` / `_gcl` / `_fbp` cookies
   - cookie inventory on load (both paths): `page.context().cookies()` may hold only `cmplz_*` and
     strictly necessary session or security cookies (for example `wordpress_test_cookie`, Cloudflare
     `__cf_bm`, a WooCommerce session after a cart action). Any `sbjs_*`, `_ga`, `_gcl*`, `_fbp`,
     `vuid` or other analytics / marketing cookie is a FAIL (#28, #33)
   - "Accept" → trackers start (`gtm.js` / `fbevents` in the network log; Consent Mode path: a
     `consent` `update` granting all four signals and `gcs=G111` hits), `cmplz_*` cookies set, banner
     closes
   - blocking path, statistics-only consent (through "View preferences"): no requests to ad or
     remarketing endpoints. Analytics runs only if it sits outside GTM, or if the `gtm.js` entry stayed
     under Statistics with the ad tags moved to a `cmplz_event_marketing` trigger
   - "Deny" in a SECOND fresh instance (`dev-browser --headless --browser cmplz-e2e-deny-$(date +%s)`; pages in one
     instance share cookies, so the Accept run would leak into it) → `cmplz_statistics=deny` /
     `cmplz_marketing=deny`, zero tracker requests (on the Consent Mode path: only cookieless
     `gcs=G100` pings on later page loads), and the same cookie inventory as on load
   - the decision is remembered after a reload; "Manage consent" is available
   - banner links → the site's policy pages (200)
   - screenshot of the banner (clip `.cmplz-cookiebanner`) for the reviewer
3. A verification table (criterion, status, evidence) in the final report.

Retest with a cache buster `?cb=<ts>` whenever a result contradicts a change you just made (#42),
and suspect a rate limit when the banner hides only for you (#43). A tester outside the configured
regions sees no banner by design (and trackers fire without a choice) when Premium geo-IP is on and
"banner in other regions" is none: test
through a proxy or VPN in the target region, or read `region` from
`/wp-json/complianz/v1/banner?lang=xx&locale=xx_XX`.

## Section 5: MULTILINGUAL (WPML)

> **Read #39 first.** If the site's MAIN language is the language the values were saved in, do NOT
> rewrite the fields in the panel into English. Fix the **source language of the strings** in String
> Translation and add translations through the `SaveTranslation` endpoint. Zero downtime on the
> main-language pages.

- Banner strings register in String Translation with source = EN regardless of the language of the
  values (#39). Either make the source language correct (preferred), or, on an English-main site,
  keep the Complianz values in English and translate the rest.
- Translate in the `complianz` context; the full string list is in #39.
- In the String Translation UI, filter by URL (`&context=complianz&search=...`); the select filter is
  unreliable. The inline popover saves on Enter.
- The wizard inherits the admin locale when the banner record is created (#9): check the texts in
  ALL front-end languages after publishing.
- Document links: point to the main-language page; WPML resolves it per language.

## Section 6: CONFIGURATION PATTERNS BY SITE TYPE

| Site type | Statistics | Records of Consent | Blocking | Notes |
|---|---|---|---|---|
| E-commerce with GTM + Meta Pixel | "Yes, with Google Tag Manager" | Yes | Script Center entry for `gtm.js` (Marketing if the container holds ad tags, see section 3); inline Pixel blocked natively | Or the Consent Mode v2 path when Google Ads is involved |
| Site running Google Ads (Google asked to fix consent) | via Complianz-owned GTM | Yes | Consent Mode v2 for Google tags; inline Pixel / LinkedIn blocked natively; non-Google tags inside GTM gated in the container | Equal-size Deny button; hardcoded GTM switched to Draft |
| Store without tracking yet ("coming later") | "Yes, but not with any of the above services" | Yes | Future hardcoded tags via Script Center | Category exists without a GTM ID (#11) |
| Service site without tracking | No | No (data minimalism) | Google Fonts / embeds / maps | Banner is mostly a formality plus blocking of fonts and embeds |
| "Only necessary" site | No | per owner | Fonts local, order attribution off (#33), unused plugins off | Rewrite the banner message (#14); clean admin cookies out of the scan (#32) |
