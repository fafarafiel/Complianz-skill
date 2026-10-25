// design-probe.js: dev-browser script that extracts the design tokens of the site's buttons, the
// current banner state, and detects Google Fonts blocked before consent.
// Run it through the wrapper, which fills in the URL (dev-browser scripts cannot read env vars):
//   bash scripts/run-design-probe.sh https://example.com/ [--headless]
// Goal: give a Complianz session everything it needs to match the banner to the site's design.
//
// Output JSON: { siteButtons[], primaryButton, bodyFont, mainFontFamily, mainFontRendersPreConsent,
//   fontChecks[], blockedGoogleFontFamilies[], fontsBlockedPreConsent, fontNote?,
//   externalFontRequestsPreConsent[], banner{} }
// - siteButtons: computed styles of real CTAs (font, weight, transform, radius, padding, bg, color, border)
// - primaryButton: heuristic "most representative" button (most frequent style)
// - fontChecks: the fonts the banner may copy (body font and every distinct button font), whether each
//   renders on this machine and whether the page actually loaded it as a web font
// - fontsBlockedPreConsent: true when one of those fonts is a Google family BLOCKED before consent
//   (data-href) that the page did not load as a web font, so visitors see a fallback until they accept
//   (a copy installed on the probing machine does not count). The banner then needs a base64 self-host.
//   fontNote: a copied font that does not render here but is not a blocked Google family.
//   See references/banner-design-match.md.

const SITE_URL = "REPLACE_WITH_SITE_URL/";
if (SITE_URL.startsWith("REPLACE_WITH")) throw new Error("Run this through scripts/run-design-probe.sh <URL>");

const page = await browser.getPage("cmplz_design_probe");
// first-time visitor view; run-design-probe.sh keeps this in a separate dev-browser instance
await page.context().clearCookies();
const fontReqs = [];
page.on('request', r => { const u = r.url(); if (/fonts\.googleapis|fonts\.gstatic/.test(u)) fontReqs.push(u.slice(0, 60)); });
// domcontentloaded + a pause: "networkidle" never settles on sites with polling widgets
await page.goto(SITE_URL + (SITE_URL.includes('?') ? '&' : '?') + "cb=" + Date.now(), { waitUntil: "domcontentloaded" });
await page.waitForTimeout(3500);

const data = await page.evaluate(async () => {
  try { await document.fonts.ready; } catch (e) {}
  const pick = el => { if (!el) return null; const cs = getComputedStyle(el);
    return { txt: (el.innerText || '').trim().slice(0, 20), fontFamily: cs.fontFamily, fontSize: cs.fontSize,
      fontWeight: cs.fontWeight, textTransform: cs.textTransform, letterSpacing: cs.letterSpacing,
      borderRadius: cs.borderRadius, padding: cs.padding, bg: cs.backgroundColor, color: cs.color,
      border: cs.border, lineHeight: cs.lineHeight }; };
  const sel = '.elementor-button, a.button, .wp-block-button__link, .wp-element-button, button.single_add_to_cart_button, .et_pb_button, .btn-primary, .btn, .button';
  const btns = Array.from(document.querySelectorAll(sel)).slice(0, 12).map(pick).filter(b => b && (b.txt || b.bg));
  // primary = the most frequent (bg, radius, color) combination among the buttons found
  const key = b => b.bg + '|' + b.borderRadius + '|' + b.color;
  const freq = {}; btns.forEach(b => { freq[key(b)] = (freq[key(b)] || 0) + 1; });
  const primary = btns.slice().sort((a, b) => freq[key(b)] - freq[key(a)])[0] || null;
  // Google Fonts blocked by Complianz (data-href)
  // --- family parser (tested offline by tests/test_design_probe_parser.mjs) ---
  const googleFamilies = href => { try {
    return new URL(href, location.href).searchParams.getAll('family')
      .flatMap(v => v.split('|')).map(f => f.split(':')[0].trim()).filter(Boolean);
  } catch (e) { return []; } };
  // --- end family parser ---
  const blocked = Array.from(document.querySelectorAll('link[data-category][data-href*="fonts.googleapis"]'))
    .flatMap(l => googleFamilies(l.getAttribute('data-href') || ''));
  const bodyFont = getComputedStyle(document.body).fontFamily;
  // does a font really render (vs a fallback)? width against monospace, not document.fonts.check
  function w(fam){const s=document.createElement('span');s.style.cssText='position:absolute;left:-9999px;font-size:60px;font-family:'+fam;s.textContent='Accept Cookies';document.body.appendChild(s);const x=s.offsetWidth;s.remove();return x;}
  const firstFam = ff => (String(ff || '').split(',')[0] || '').replace(/['"]/g, '').trim();
  // a generic or system family (sans-serif, system-ui, -apple-system...) always renders: nothing to test
  const generic = f => /^(serif|sans-serif|monospace|cursive|fantasy|system-ui|math|emoji|fangsong|ui-[a-z-]+|-.*|blinkmacsystemfont|segoe ui|helvetica neue|helvetica|sf pro text|sf pro display)$/i.test(f);
  const rendersFam = f => !f || generic(f) || w("'" + f + "',monospace") !== w('monospace');
  const mainFam = firstFam(bodyFont);
  const renders = rendersFam(mainFam);
  // web fonts the page really loaded (a font installed on this machine is not in document.fonts)
  const loadedFaces = new Set();
  try { document.fonts.forEach(f => { if (f.status === 'loaded') loadedFaces.add(firstFam(f.family).toLowerCase()); }); } catch (e) {}
  // the banner may copy the body text or any button style (hero CTA, shop buttons), so check them all
  const allButtons = Array.from(document.querySelectorAll(sel)).slice(0, 300);
  const copied = [...new Set([mainFam, ...allButtons.map(el => firstFam(getComputedStyle(el).fontFamily))].filter(Boolean))];
  const fontChecks = copied.map(f => ({ family: f, renders: rendersFam(f), webFontLoaded: loadedFaces.has(f.toLowerCase()) }));
  const cb = document.querySelector('.cmplz-cookiebanner');
  const g = el => el ? { font: getComputedStyle(el).fontFamily, weight: getComputedStyle(el).fontWeight,
    radius: getComputedStyle(el).borderRadius, bg: getComputedStyle(el).backgroundColor,
    color: getComputedStyle(el).color, border: getComputedStyle(el).border } : null;
  return {
    siteButtons: btns, primaryButton: primary, bodyFont, mainFontFamily: mainFam,
    mainFontRendersPreConsent: renders, fontChecks, blockedGoogleFontFamilies: [...new Set(blocked)],
    banner: cb ? { present: true, accept: g(cb.querySelector('.cmplz-accept')), deny: g(cb.querySelector('.cmplz-deny')) } : { present: false }
  };
});
// blocked = a font the banner may copy is one of the blocked Google families and the page did not load
// it as a web font (rendering is not used here: the family may be installed on the probing machine).
// A non-rendering font that is not a blocked Google family gets a note instead.
const norm = s => String(s).trim().toLowerCase();
const blockedSet = new Set(data.blockedGoogleFontFamilies.map(norm));
data.fontsBlockedPreConsent = data.fontChecks.some(c => blockedSet.has(norm(c.family)) && !c.webFontLoaded);
const unexplained = data.fontChecks.filter(c => !c.renders && !blockedSet.has(norm(c.family))).map(c => c.family);
if (unexplained.length)
  data.fontNote = unexplained.join(', ') + " does not render but is not among the blocked Google families: check its source by hand";
data.externalFontRequestsPreConsent = [...new Set(fontReqs)];
console.log(JSON.stringify(data, null, 1));
