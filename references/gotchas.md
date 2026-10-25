# Gotchas: Complianz and automation traps

Collected across ten production deployments (Complianz 7.5.2 to 7.6.6, June to October 2026).
Numbers are referenced from `SKILL.md` and `golden-path.md`. Admin labels are quoted from the
English UI; your version or locale may word them slightly differently.

## A. Complianz admin panel (React SPA)

1. **An expiring REST nonce sends saves into the void.** Saves go to
   `POST /wp-json/complianz/v1/fields/set`. Navigating by `#hash` does NOT reload the SPA, so the
   nonce goes stale and the server answers `403 rest_cookie_invalid_nonce`. The setting looks
   saved but is not. Symptoms: the EU region "disappears", `consenttype` becomes `other`, the
   banner never shows even though everything looks enabled. **Fix:** hard reload
   `admin.php?page=complianz&fresh=<timestamp>#...` before every batch of saves, and capture the
   `fields/set` response while debugging (`request_success: true`?). This one cost hours.
2. **Clicks do not always register.** Checkboxes and radios are `button[role=checkbox]` without an
   `<input>`. Read state ONLY from `aria-checked` / `data-state`. Click with a Playwright locator
   (trusted event); if that fails, DOM-click through `evaluate` (one site's radios reacted only to
   a DOM click). Read the state back after every click.
3. **`.fill()` does not commit to React state**, so "Save" stores the old value. Fix: native value
   setter + `dispatchEvent(new Event('input', {bubbles: true}))` + `change` / `blur`.
4. **"Save and continue" is an `<a class="button-primary">`**, not a `<button>`. A button locator
   times out.
5. **Script Center: saving the entry is not saving.** You must also click the GLOBAL "Save" of the
   page. Three sections have identical "Add new" buttons, so it is easy to add to the wrong one
   (remove a stray entry with the "Delete" button inside its expanded panel). See also #31.
6. **IDs that start with a digit** (`#0_url`, `#12-xx`) are invalid CSS selectors. Use
   `[id="0_url"]`.
7. **The color picker is react-color inside a Radix popover** (7.5.x and later). Per swatch: click
   `button[aria-haspopup="dialog"]` inside `.cmplz-field-wrap.cmplz-colorpicker` → set the hex in
   `[data-radix-popper-content-wrapper] input[id^="rc-editable-input"]` with the native setter →
   `input` / `change` → Enter → Escape. Groups: Background, Text, Toggles, Accept, Deny, Settings,
   each with two or three sub-swatches (background, border, text). Do at most four to six swatches
   per script (see #52). The panel shows AA / AAA contrast badges; check them after each change.
8. **Website scan "Start" (WSC) registers the domain with an external Complianz service** and asks
   for an e-mail confirmation. Clicking "Start" throws you out of the wizard to the dashboard with a
   registration modal. The local "Scan" button is disabled without WSC (7.5.7 and later). The scan
   is NOT required: service auto-detection (`cmplz_detected_*`) works without it. After coming back
   the wizard may show 0% progress, but answers ARE saved (they persist per step).
9. **The wizard inherits the ADMIN's locale** for banner texts: an admin whose profile language
   differs from the site language (say a German profile on a French site) produces a banner in the
   admin's language. Check the front end in EVERY language after publishing.
   For WPML sites see #39.
10. **Country and similar choices are a Radix combobox** (`button.cmplz-select-group__trigger`),
    not a `<select>` or react-select; the value sits in a `<span>` inside. Often pre-filled.
11. **"Statistics: Yes, with Google Tag Manager" makes the GTM container ID required.** If the site
    has no tracking yet ("we will add it later"), pick **"Yes, but not with any of the above
    services"**. That activates the statistics category without a required ID and without
    injecting code. The category works in the banner (`cmplz_statistics=allow/deny`); block the
    future hardcoded tracking through Script Center.
12. **"Link to menu":** the default option (geo-IP redirect) does NOT touch the site's menus; the
    "No, select a menu" option FORCES you to assign links to a menu. With policies already in the
    footer, keep the default.
13. **Policy links on the banner: duplicates and ghost links (version dependent).**
    - Pointing BOTH "Cookie policy" and "Privacy statement" to the same page renders two identical
      links (`a.cmplz-link.cookie-statement` and `a.cmplz-link.privacy-statement`). Prevention:
      with a single policy page, set Cookie policy = that page and **Privacy statement = None**
      (Cookie policy has no "None" option, Privacy statement does).
    - Before 7.5.7.3, "None" alone could still leave the link: the server-side template became
      `{title}` / `href="#"`, but the inline config `page_links` kept the URL and `complianz.js`
      filled it in. Fix then: CSS hide
      `.cmplz-cookiebanner a.cmplz-link.privacy-statement{display:none !important}`.
    - From 7.5.7.3, `{title}` ghost links get the `cmplz-hidden` class automatically, and 7.6.6
      showed a single correct link with no CSS. Check computed visibility BEFORE adding any hide rule.
    - With Privacy statement = None the wizard skips the "Data Protection Officer", "Purpose" and
      "Sharing of data" screens. That is expected.
14. **Check the default texts in the site's language.** In some translations the "Save
    preferences" label reads almost like "Accept" (seen in at least one translation); rename it under
    Consent Banner → Text. On an "only necessary" site the default banner message
    still talks about browsing behavior and unique identifiers, which is then untrue: rewrite
    `message_optin` (CKEditor field: click, select all, type, Save).
15. **Running the wizard without clicking (WP-CLI).** When the React UI is painful (host rate
    limits, slow panel), save the wizard answers with the same function the panel uses, so the
    hooks `cmplz_after_save_field`, `cmplz_after_saved_fields` and `cmplz_finish_wizard` still run:

    ```php
    wp_set_current_user(1);                                   // an administrator
    $types = array_column(COMPLIANZ::$config->fields, 'type', 'id');
    $fields = [['id'=>'regions','value'=>'eu','type'=>$types['regions']], /* ... */];
    $r = new WP_REST_Request('POST','/complianz/v1/fields/set');
    $r->set_param('fields',$fields); $r->set_param('nonce', wp_create_nonce('cmplz_react')); $r->set_param('finish', true);
    cmplz_rest_api_fields_set($r);                            // needs get_lock_user() == current user (fine on a fresh install)
    // policy page as "Existing page":
    $d = new WP_REST_Request('POST'); $d->set_param('pageId',$policy_page_id); $d->set_param('type','cookie-statement');
    $d->set_param('nonce', wp_create_nonce('cmplz_react')); COMPLIANZ::$documents_admin->update_custom_legal_document_id($d);
    ```

    Verify `get_option('cmplz_options')` field by field (`regions` is stored as the list `["eu"]`,
    which is fine). Field ids: loop over `COMPLIANZ::$config->fields` (`menu_id`, `id`, `type`,
    `options`). After a CLI save also check #22.

## B. Banner CSS and styling

16. **Complianz "Custom CSS" (ACE editor): saved is not shipped.**
    - Observed on 7.5.2: the ACE editor CAN be saved by automation: enable the "Use custom CSS" toggle, call
      `window.ace.edit('ace-editor').setValue(css, -1)`, nudge it dirty (insert and remove one
      character), click Save. Critical condition: a FRESH nonce (#1); a stale nonce gives
      `403 do_action/update`, which looks exactly like "ACE does not save". After a good save
      Complianz regenerates `uploads/complianz/css/banner-1-optin.css?v=N` and bumps `N` (#19).
    - Observed on 7.6.0: the value persists in the config (it survives a reload) and the toggle
      switches on, but the rules do NOT reach the front end: `banner-1-optin.css` is not regenerated from the
      custom CSS, there is no separate file (`banner-1-optin-custom.css` = 404) and nothing inline
      in `wp_head`. Re-saving the banner does not help (check #22 first if the banner CSS file is
      missing altogether). **Do not spend time on ACE for styling; use the Customizer (#17).**
17. **Customizer "Additional CSS": the setting id is theme-namespaced, `custom_css[<theme>]`.** This
    is the reliable path (WordPress core, guaranteed output in `<style id="wp-custom-css">`). Trap:
    `wp.customize('custom_css')` returns `undefined`. Auto-detect with
    `wp.customize.each(s => { if (/^custom_css(\[|$)/.test(s.id)) id = s.id })`, set with
    `wp.customize(id).set(value)` (bypasses the CodeMirror sync), keep it idempotent with a marker
    block, publish with `#save` (after `b.disabled = false`). The Customizer loads slowly; wait
    about 9 s before touching `wp.customize`. Implemented in `scripts/apply-banner-css.py`.
18. **A CSS marker containing `<` or `>` can be EATEN on save.** The worst kind of failure:
    everything reports success (the script prints `set: OK`, the button says "Published",
    `#wp-custom-css` on the front end contains the marker) but `document.styleSheets` has zero
    `cmplz` rules. Cause: a security or hardening layer on the site (a plugin or the host WAF; the
    exact culprit was not isolated) sanitizes the saved text as HTML, so everything from the first `<` to the next `>` disappears.
    With a marker like `/* >>> BANNER START <<< */` the next `>` sits in the END marker, so all
    the CSS in between vanishes and the database keeps an unterminated comment (one more `/*`
    than `*/`). In the middle of a stylesheet that would comment out everything below it.
    **Rule:** no decorative `<` or `>` in any text injected through a WordPress field.
    `scripts/apply-banner-css.py` refuses such CSS, uses `/* --- CMPLZ BANNER CSS START --- */`
    markers, and reads the front end back. **Always verify on the front end, not by the save
    response:** count rules in `document.styleSheets` for `#wp-custom-css` and compare the `/*`
    and `*/` counts.
19. **Complianz custom CSS lands in a FILE, `banner-1-optin.css?v=N`, not inline** (observed on 7.5.2). A save
    bumps `v`, so fresh HTML loads the new file. A host page cache keeps serving the old HTML with
    the old `?v=`, so the fix is invisible for cached visitors until the cache expires. Verify with
    a cache-disabled browser (`Network.setCacheDisabled`) and curl the file without a query string.
    Same stale-cache mechanism as #42.
20. **A brand font on the pre-consent banner needs a base64 self-host.** When a font the banner copies
    (body text or buttons; on Hello Elementor the body often uses a system stack while buttons use a
    Google Font) is a Google Font that Complianz blocks (`data-href`), the banner (shown BEFORE consent) renders
    a fallback; `font-family: 'Nunito'` in CSS does not help because the font never loads. Fix:
    `@font-face` with a base64 data URI (same origin, loads before consent, no external call):
    `scripts/font-to-base64.py "Nunito" "300 700" NunitoBanner`. Use a UNIQUE family name so
    it does not collide with the blocked external one. Detect real rendering by comparing the
    rendered width against `monospace`; `document.fonts.check` returns false positives (true for
    fonts that never loaded). Do NOT use the Complianz "self-host Google Fonts" option as the fix:
    observed on 7.6.0, it did not fetch fonts enqueued by Elementor or the theme and left the external `href` live
    without consent, which is a privacy regression worse than blocking.
21. **A white square around the banner's "×" is someone else's focus `box-shadow`.** Complianz
    focuses `div.cmplz-close` when the banner opens (accessibility), so `:focus-visible` is true in
    Chrome. A global focus rule from the theme or a plugin (`box-shadow: 0 0 0 4px #fff`) draws a
    white square on a dark banner. `outline` alone does not fix it: add `box-shadow: none !important`
    for `.cmplz-close:focus` and `:focus-visible`, plus your own outline in the brand color.
22. **The banner CSS file is not generated → banner stays hidden (`cmplz-hidden`).** After a wizard
    save from the CLI, `uploads/complianz/css/` was empty; the JS waits for
    `banner-<id>-<consenttype>.css` (the config holds the pattern `banner-{banner_id}-{type}.css`,
    which is normal; the JS fills it in). Fix:
    `delete_transient('cmplz_generate_css_active'); (new CMPLZ_COOKIEBANNER(1))->generate_css();`
    → `banner-1-optin.css`.

## C. Script blocking and detection

23. **Complianz does NOT block GTM with "your own implementation"**
    (`configuration_by_complianz=no`). That is deliberate (they expect a GTM integration via cmplz
    events). Block a hardcoded GTM with a Script Center entry; the substring
    `googletagmanager.com/gtm.js` also matches the inline loader. Pick the entry's category by what
    the container holds: once released, every tag inside fires, so a container with ad or remarketing
    tags belongs under Marketing (or those tags move to a `cmplz_event_marketing` trigger). (For
    Consent Mode see #37.)
24. **Inline Meta Pixel and Google Fonts are blocked natively** (`type="text/plain"` / `data-href`;
    Google Fonts only when they are selected under Services with self-hosting off).
    To verify in HTML, find the nearest `<script` / `<link` BEFORE the snippet: `type="text/plain"`,
    or `data-href` instead of `href`, means blocked. A `data-service` attribute alone does NOT mean
    blocked (a tag can carry it and still run).
25. **Known tracker snippets in Elementor Custom Code are blocked natively too** (a GTM snippet there
    is not, see #23). Inline GA4
    (`googletagmanager.com/gtag/js?id=G-...` created via `createElement`), Meta Pixel
    (`fbevents.js`) and LinkedIn Insight (`snap.licdn.com`) got `type="text/plain"` + `data-category`
    (statistics / marketing / marketing) without any Script Center entry. Wizard answers that did
    it: Statistics "Yes, with Google Analytics" + "Complianz adds GA" = No, social Facebook +
    LinkedIn, advertising = Yes. Always verify with the list of `<script>` tags containing the IDs
    plus zero requests before consent.
26. **`<noscript>` fallbacks (GTM iframe, Meta `img` pixel) are not blocked.** They fire for
    visitors without JavaScript. Marginal (the banner needs JS too), but tell the site owner.
27. **The Elementor "Google Maps" widget is NOT auto-blocked**, even with "Services → third-party
    services = Yes + Google Maps" in the wizard. The widget renders
    `<iframe src="maps.google.com/maps?q=...">` (plus `maps.googleapis.com/maps/api/js?key=`), a
    pattern outside the auto blocklist. Fix: Script Center → "Block a script, iframe or plugin" →
    URL `google.com/maps` (matches `maps.google.com/maps` and `www.google.com/maps/embed`),
    category Marketing, enabled. After that the iframe gets `data-category="marketing"
    data-service="google-maps"` and a placeholder.
28. **Elementor background video from Vimeo sets `vuid` BEFORE consent.** Background videos
    (`background_video_link` on vimeo.com) load the player through the Vimeo Player SDK from JS, so
    Complianz does not detect them (`cmplz_detected_thirdparty_services` showed only Google Fonts).
    Measured in a fresh context: analytics cookie `vuid` on `.vimeo.com` without consent. Ticking
    "Vimeo" in the wizard risks an empty hero before consent. Native fix: the Elementor control
    **`background_privacy_mode = yes`** ("Privacy mode" next to the background video), so the SDK
    gets `dnt: true` and the iframe `dnt=1`; `vuid` disappears (Cloudflare security cookies
    `__cf_bm` / `cf_clearance` may remain). In bulk: walk each document's `_elementor_data`, set
    the control on every background video, save through the Elementor Document API, read back.
    The player still connects to vimeo.com before consent, so how to cover it (in the policy on a
    legitimate-interest basis, or behind consent) is the owner's or counsel's call; do not tick it in
    the wizard without accepting an empty hero before consent.
29. **A previous consent tool may be an Elementor snippet, not a plugin.** On one site the old CMP
    lived as an `elementor_snippet` post (`_elementor_location=elementor_head`) loading an external
    script; the plugin list was clean. Pre-flight row 3 (golden-path section 0) MUST include
    `wp post list --post_type=elementor_snippet --post_status=any --fields=ID,post_title` plus a runtime network
    audit (`page.on('request')`). gtag / consent mode / sbjs calls may come from such a script and
    disappear with it (removal = trash the post + flush the Elementor cache, no files).
30. **Custom lazy-loaded reCAPTCHA must not be combined with Complianz reCAPTCHA blocking.** If the
    site deliberately does not consent-gate reCAPTCHA and instead dequeues `api.js` and loads it on
    form intent from custom code, there is a two-way trap:
    (A) Adding a reCAPTCHA Script Center entry, or enabling reCAPTCHA blocking, makes the blocker
    substring-match the CONTENT of inline scripts too (as with the inline GTM loader in #23), so the lazy loader gets `text/plain`
    and the form silently stops sending for everyone without marketing consent. It fails closed,
    and the admin who flipped the toggle has consent in their own browser and sees a working form.
    (B) Conversely, runtime injection bypasses the Complianz output-buffer rewrite, so Complianz
    never gates that loader. If consent gating becomes a requirement, rewrite the loader on the
    Complianz consent API (`cmplz_run_after_all_scripts`); do not add a block entry. In E2E assert:
    the loader has no `type="text/plain"` with consent denied, focusing the form loads `api.js`,
    and submit works.
31. **A Script Center block entry is a `<details>` accordion.** Three sections, each with "Add new";
    the "Block a script, iframe or plugin" section is the second button (index 1). "Add new" creates
    a collapsed "general" entry → expand it by clicking `summary` → fields: Name, `input[id="0_url"]`
    (URL, see #6), async checkbox, Category radio group (only Statistics / Marketing; functional is
    always on). The accordion can collapse between scripts; name and URL SURVIVE in React state, but
    reopen through `details > summary` before clicking the category.
32. **If the scan was run (it is skipped by default), it picks up cookies of the LOGGED-IN admin** (Automattic `tk_qs` / `tk_ai`,
    Mixpanel `mp_*`, `crumb`, `theme-mode`, hosting panel and Elementor cookies) and puts them in the
    `[cmplz-cookies]` table as Statistics or Miscellaneous. Visitors never get them, but an "only
    necessary" policy becomes contradictory. Fix: wizard → Cookie descriptions
    (cookiedatabase.org) → expand the service → "Delete service" (Automattic; Sourcebuster only once
    WooCommerce order attribution is off or consent-gated, #33); under
    "Unknown service" expand each entry (click `summary`) → "Delete". Override
    `window.confirm = () => true` first, otherwise the native modal blocks automation. Check the
    table on the front end as an anonymous visitor.

## D. Cookies and scripts you did not expect ("only necessary" sites)

33. **WooCommerce order attribution (`woocommerce_feature_order_attribution_enabled`) sets `sbjs_*`
    cookies before consent wherever it is on, unless it is gated through the WP Consent API** (on by
    default since WooCommerce 8.5, with or without other analytics). Switch it off
    (`PUT wc/v3/settings/advanced/woocommerce_feature_order_attribution_enabled {"value":"no"}`, or
    the order attribution switch under WooCommerce > Settings > Advanced > Features), or
    prove that it waits for consent (for example through the WP Consent API, if your WooCommerce and
    Complianz versions support it) by checking the cookies before consent (golden-path section 4).
    Never leave it on and unverified.
34. **Hostinger Reach** loads `cdn-reach.hostinger.com/js/embed.js` on every page even when it is
    not connected to an account. If unused, deactivate it (the site owner's call) instead of asking
    for marketing consent for an unused tool.
35. **Elementor Pro writes `localStorage.elementor = {"pageViews":N}`** on the front end whenever
    any popup exists (even a menu popup). No identifier and no transmission; whether it counts as
    strictly necessary or functional storage is the owner's or counsel's call, but describe it in the
    policy either way.
36. **Stripe.js and the PayPal SDK load on product and cart pages** regardless of where the express
    checkout buttons are placed (`express_checkout_button_locations`; set it through REST, the React
    settings panel sometimes does not persist it). Describe in the policy where payment scripts load.

## E. Google Consent Mode v2

37. **The Consent Mode v2 field is CONDITIONAL on who owns the GTM snippet** (7.5.2). "Do you want to
    enable Google Consent Mode V2?" appears in the wizard (`#wizard/statistics-configuration`) ONLY
    when "Do you want Complianz to add Google Tag Manager?" = Yes. Switching that to No (the natural
    reflex when GTM is already hardcoded) removes the field, and on 7.5.2 it existed nowhere else:
    the Integrations page has no Consent Mode switch (only Services, Plugins, Script Center). The
    Consent Mode path was not re-run on 7.6.x, and the "Complianz adds Google Analytics" branch was
    not tested.
    Consequence: native Consent Mode requires the GTM snippet to belong to Complianz. Switch the
    hardcoded copy off, otherwise GTM loads twice (Complianz itself reports a duplicate tracking
    code). Typical location: Elementor Pro → Custom Code, with separate "head" and "body" entries;
    switch them to Draft (fully reversible). Leave "Will you be using our Tag Manager template?" =
    No when the site has its own container with its own tags.
38. **Verify Consent Mode by its signals, not by the presence of a script.** Google's guide "Verify
    consent mode implementation" (support.google.com/google-ads/answer/14218557) uses Tag Assistant:
    the earliest Consent event must set all four signals `ad_storage`, `ad_personalization`,
    `ad_user_data`, `analytics_storage` with "On-page Default" = Denied; after "Accept" the most
    recent Consent event sets the same four with "On-page Update" = Granted; then check which tags
    fired or were blocked. Without Tag Assistant, read the `dataLayer` `consent` `default` and
    `update` pushes: all four keys must be present.

    In the network log, requests to `region1.google-analytics.com/g/collect` and
    `pagead2.googlesyndication.com/ccm/collect` carry `gcs`, which covers only the storage pair:

    | Value | Meaning |
    |---|---|
    | `gcs=G100` | `ad_storage` **denied** + `analytics_storage` **denied** (before consent) |
    | `gcs=G111` | both **granted** (after "Accept") |
    | `npa=1` | non-personalized ads |

    The hits also carry `gcd`, an encoded form of the full consent state; read it through Tag
    Assistant rather than by hand. A change from
    `G100` to `G111` alone does NOT prove Consent Mode **v2**: `ad_user_data` and
    `ad_personalization` can still be missing, and those two are what Google's "fix your consent
    banner" e-mails are about.

    **Do not "fix" GTM loading BEFORE consent.** Under (advanced) Consent Mode that is the expected
    behavior: the
    tag loads, receives `denied` signals and sends cookieless pings (conversion modeling). For
    Google tags the violation would be cookies: check `_ga` / `_gcl` / `_fbp` in `document.cookie`
    and the `gcs` value, not the request itself. Any request from a NON-Google tag before consent is
    still a violation. Consent Mode does NOT cover Meta Pixel; Complianz blocks an inline Pixel
    natively (`<script type="text/plain" data-service="facebook" data-category="marketing">`), while a
    Pixel inside GTM must be gated in the container (golden-path section 3B).
    **Measurement trap:** `page.context().clearCookies()` on a page that just went through "Accept"
    can return the pre-clear state, so a "deny" test showed `_ga=true` and looked like a violation.
    Run the deny test in a **separate, fresh dev-browser instance** (`--browser cmplz-e2e-deny-$(date +%s)`; pages in one
    instance share cookies) and assert `cookies.length === 0` BEFORE loading the site.

## F. Multilingual (WPML)

39. **WPML: fix the string's SOURCE LANGUAGE instead of rewriting the values in the panel.**
    Symptom: the banner on the secondary-language pages shows texts in the main language. Cause:
    Complianz registers banner strings in WPML with `data-language="en"` regardless of the language
    the values are actually in (the wizard inherits the admin locale, #9). On a site whose main
    language is, say, German, with English as the second language, `/en/` renders the "source",
    which is the German text.

    **Costly path:** switch every field in Complianz to English and add the main language as a
    translation. On a site whose main language is not English, the homepage shows an English banner
    between those two steps.

    **Zero-downtime path:** String Translation → select the strings → select
    **`#icl_st_change_lang_selected` → "Change the language of selected strings" → the correct
    source language**. Nothing changes in Complianz, and the main-language pages render the source
    exactly as before. Then add translations for the other languages. Every intermediate state is
    safe: until a translation exists, the secondary language falls back to the source as before.

    It is **Select2, not a plain `<select>`**: there is no separate button, the action fires on
    `change`. A native `dispatchEvent` does NOT work; use
    `jQuery('#icl_st_change_lang_selected').val('de').trigger('change')` (the code of the language the
    strings are actually written in, here `de`).

    **Bulk-save translations through the endpoint instead of the UI.** Payload shape taken from
    `wpml-string-translation/dist/js/main-ui/app.js` (search for `saveTranslation`):

    ```js
    const ep = window.wpml_st_main_ui.endpoints.saveTranslation;   // {endpoint, nonce}
    const body = new URLSearchParams();
    body.append('action', 'wpml_action');
    body.append('nonce', ep.nonce);
    body.append('endpoint', ep.endpoint);                          // WPML\ST\Main\Ajax\SaveTranslation
    body.append('data', JSON.stringify({ id: STRING_ID, translation: TEXT, lang: 'en' }));
    await fetch(window.icl_vars.ajax_url, { method:'POST', credentials:'same-origin', body });
    // success: {"success":true,"data":<translation record id>}
    ```

    The keys are exactly `id` / `translation` / `lang`; `string_id`, `value` or `language` return
    `{"success":false,"data":"invalid data"}`. All banner strings save in one pass (about 5 s)
    instead of one DOM round per string.

    **Complianz banner strings to translate (context `complianz`):** `header`, `revoke`, `dismiss`,
    `accept`, `accept_informational`, `save_preferences`, `view_preferences`, `message_optin`,
    `message_optout`, `category_functional`, `category_all`, `category_stats`, `category_prefs`,
    `functional_text`, `statistics_text`, `statistics_text_anonymous`, `preferences_text`,
    `marketing_text`, `cookie_retention`.

## G. Verification pitfalls

40. **`offsetParent === null` on a `position: fixed` banner** is a false "banner not visible". Check
    the `cmplz-hidden` class and computed `display` instead.
41. **HTML-level tracker checks have blind spots.** A plain substring search for `fonts.googleapis`
    matches `<link rel="dns-prefetch" href="//fonts.googleapis.com">` (a DNS hint, no font transfer,
    no cookies) and can miss the `href` vs `data-href` difference. When Complianz blocks Google
    Fonts, the stylesheets carry `data-href="https://fonts.googleapis.com/..."` +
    `data-category="marketing"` instead of `href`. Not every `data-` attribute is Complianz: lazy-loaders
    and optimizers also move URLs into `data-src`, `data-lazy-src` or delayed-style attributes, and
    those load on scroll or interaction WITHOUT consent. `scripts/verify.sh` counts only Complianz's
    own attributes as blocked (`data-src-cmplz` or its alias `data-cmplz-src`, or `data-href` on a tag
    marked `data-category` / `data-service`) and fails on the others; it skips resource hints, checks EVERY occurrence and
    prints the first live tag (a FAIL can point at a reference that never loads anything, for example
    a URL inside a config script: read the tag). The authoritative proof is a browser network audit
    before consent (`page.on('request')`) after scrolling to the bottom and moving the mouse: zero
    requests = blocking works. A DNS prefetch before consent is a
    negligible margin (name resolution only).
42. **A host page cache serves STALE HTML after a Script Center change.** (Seen with a host nginx
    cache, `x-cache-status: HIT`, behind Cloudflare with `cf-cache-status: DYNAMIC`.) Blocking looks
    broken (iframe still has `src`, requests to Google before consent). Flushing the Redis object
    cache does NOT clear that layer, and WordPress cannot purge it without a page-cache plugin.
    **ALWAYS retest a fresh render with a cache buster** `/page/?cb=<ts>`: if `?cb=` shows the
    block and the bare URL does not, it is the cache. Purge in the host panel or wait for the TTL.
43. **`geoip: 1` + a host rate limit (HTTP 429) = the banner does NOT show (for you).** With
    `geoip == 1`, `complianz.js` makes an XHR to `wp-json/complianz/v1/banner?lang=...` before
    `conditionally_show_banner()`. A 429 response (some LiteSpeed hosts throttle bursts from one IP,
    and the block can last more than 20 minutes) breaks `JSON.parse`, so the banner stays
    `cmplz-hidden`. That is a tester artifact, not a defect: check from ANOTHER IP
    (`curl .../wp-json/complianz/v1/banner?lang=xx&locale=xx_XX` from a server → 200,
    `region: eu`, `consenttype: optin`) and ask for a test from a phone on mobile data. Run browser
    E2E as ONE pass (load → state → Accept). Not to be confused with region filtering: a tester outside
    the configured regions sees no banner by design, and trackers fire without a choice (golden-path
    section 4).

## H. Hosting, WAF, access

44. **Aggressive host WAF:** `/wp-json/` + Basic Auth → 406, only `?rest_route=` works. The WAF also
    scans upload CONTENT (admin-ajax, file manager plugins): `.htaccess` always blocked; PHP with
    tokens like `eval`, `'unsafe-inline'` or long CSP strings blocked cumulatively. SFTP / FTPS
    bypasses the WAF. Agree on an emergency file-editing channel (SFTP or FTPS before a file manager
    plugin) during pre-flight.
45. **A mu-plugin with a parse error = white screen for the WHOLE site** (mu-plugins have no recovery
    mode), and it also kills file manager plugins, so you cannot fix it with the tool that broke it.
    ALWAYS run `php -l` before uploading, and have an SFTP / FTPS recovery channel BEFORE you upload. If one
    PHP file can be loaded from two places, a `define()` + `return` guard does NOT prevent
    "Cannot redeclare": PHP binds top-level function declarations at compile time, before the
    runtime check. Wrap EVERY function in `if (!function_exists(...)) {}` and keep the
    `define()` + `return` guard for hook registration.
46. **Imunify360 hosts:** parallel SSH sessions or failed auth attempts can ban your IP on SSH and
    HTTP (file transfer survived). Avoid failed attempts: with a key, offer only that key
    (`-o IdentitiesOnly=yes -i <key>`); on a password-only account, stop the client from offering keys
    first (`-o PreferredAuthentications=password`). Use one connection at a time.
47. **wp-admin sessions can expire after a few minutes** (seen repeatedly with ASE Pro and on some
    shared hosts). The `#wp-auth-check-wrap` overlay swallows clicks. Write atomic scripts: log in at
    the start of every longer block, and after a `fresh=` reload check you did not land on
    `wp-login.php`.
48. **REST can be sensitive to a missing `User-Agent`**; send `User-Agent: Mozilla/5.0`.
49. **Free and Premium active at the SAME time.** Premium installed while the free plugin was still
    active: both ran (symptoms: an unexpected `geoip: 1` together with `uploads/complianz/maxmind` and
    `cmp` directories, and a JS version different from the plugin version; `geoip: 1` alone just
    means Premium geo-IP is on). Before starting: `wp plugin list | grep -i complianz`.
    Keep Premium, DEACTIVATE the free one (both share `cmplz_options`, nothing is lost).
50. **Installed is not configured.** Several sites had Complianz installed but the wizard was never
    finished: `consenttype: "other"`, `documents: []`, no banner, while `cookieblocker.min.css` still
    loaded on the front end (misleading). Check `GET /wp-json/complianz/v1/banner` during pre-flight.

## I. dev-browser automation

51. **Do NOT use the page name `main`.** It is shared between sessions (pages were taken over mid-run
    twice). Use a dedicated name per site: `browser.getPage("site-cmplz")`.
52. **Scripts are killed after 30 s by default.** Pass `--timeout 120` for longer scripts, and still
    split UI loops into chunks (six operations or fewer). `snapshotForAI()` on heavy admin pages can
    also time out or throw; fall back to a manual DOM dump through `evaluate`.
53. **Screenshots take relative names only** (absolute paths are rejected); files land in
    `~/.dev-browser/tmp/`.
54. **The sandbox is QuickJS, not Node.js:** no `process` (so environment variables never reach a
    script; generate the script with the values filled in, as `run-design-probe.sh` and
    `apply-banner-css.py` do), no `require('fs')`. `page.evaluate` takes ONE argument (pass an array
    or object for several). `postData()` / `postDataJSON()` can throw buffer errors; patch
    `window.fetch` in the page context to capture request bodies instead.
55. **`page.route()` can hang navigation** in dev-browser; do not use it for E2E.

## J. Process (what made deployments long)

56. **No pre-flight = discovering everything on the way.** Tracking stack, WPML, admin locale, WAF,
    palette: all of it can be checked in 10 minutes BEFORE the wizard (golden-path section 0).
57. **Collect the site owner's decisions in ONE question** (visitor regions, blocking vs Consent Mode,
    position, Records of Consent, fonts) instead of interrupting the work with a series of follow-ups.
58. **Every save → immediate read-back** (DOM, response, or curl of the front end). Trusting clicks
    costs hours of "why is the banner not showing".
59. **One session = one site = one browser page.** Working on two sites in parallel in one browser
    leads to page takeovers and mixed-up contexts.
