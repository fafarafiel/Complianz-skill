#!/usr/bin/env python3
"""apply-banner-css.py: generate a dev-browser script that injects the banner CSS through the
WordPress Customizer "Additional CSS" (custom_css[<theme>]), publishes it, and reads the front end
back. Reliable output (wp_head, <style id="wp-custom-css">), unlike the Complianz "Custom CSS"
editor, which on 7.6.0 was observed storing the value but never outputting it (gotchas #16, #17).

Why the Customizer and not the Complianz editor or a mu-plugin:
- Complianz editor (ACE): the value persists in the config, but on 7.6.0 banner-1-optin.css was not
  regenerated from it, so the rules never reached the front end.
- mu-plugin over SFTP: file access is often unavailable, and a parse error takes the whole site down.
- Customizer custom_css[<theme>]: WordPress core, guaranteed output, set through the wp.customize
  API (bypasses the CodeMirror sync), idempotent thanks to the marker block.

Usage (https only; CMPLZ_ALLOW_HTTP=1 allows http:// for a local test site):
  ( umask 077; CMPLZ_URL=https://site.tld/ python3 scripts/apply-banner-css.py banner.css > apply.js )
  dev-browser --timeout 120 < apply.js
  rm apply.js

Login: the script reuses the dev-browser profile's wp-admin session. If that profile is not logged in,
it logs in with CMPLZ_USER / CMPLZ_PASS when both are set, otherwise it stops with NOT_LOGGED_IN.
Credentials are typed only into a login page under CMPLZ_URL (same origin, https); a login page
anywhere else stops the run with LOGIN_ORIGIN_MISMATCH.
When you pass credentials they end up inside apply.js: keep the file private and delete it afterwards.

Before changing anything it saves the current Additional CSS to ~/.dev-browser/tmp/
(cmplz-custom-css-backup-<timestamp>.css) and stops with PENDING_CHANGES if the Customizer holds
unsaved or scheduled changes, because publishing would push those too.

The script is IDEMPOTENT: it replaces the block between the markers and leaves the rest of the
site's Additional CSS untouched. If it finds a damaged marker (start without end) it stops with
STALE_MARKER and changes nothing, so you can clean it up by hand. When the front-end read-back does
not show the rules, the script fails with FRONT_CHECK_FAILED (a CSS optimizer that combines inline
CSS, such as LiteSpeed Cache, WP Rocket or Autoptimize, can remove the wp-custom-css tag: purge or
exclude it and check again).

NO_CUSTOMIZE or NO_CSS_SETTING means the Customizer did not load or has no Additional CSS: typical for
block themes (use Site Editor > Styles > Additional CSS, or a WPCode CSS snippet), but also shown for a
user without the customize capability or a login / error page.
"""
import sys, os, re, json

MARKER_LABEL = 'CMPLZ BANNER CSS'

if len(sys.argv) < 2:
    sys.stderr.write(__doc__); sys.exit(2)
css = open(sys.argv[1], encoding='utf-8').read()
# gotcha #18: text saved through the Customizer can be sanitized as HTML; everything from '<' to the
# next '>' disappears while the save still reports success. Banner CSS never needs these characters.
if '<' in css or '>' in css:
    sys.exit("ERROR: the CSS contains '<' or '>'. Security or hardening layers (a plugin or the host WAF) "
             "can eat such text on save (gotcha #18). Remove them, e.g. turn the child selector 'A > B' "
             "into the descendant selector 'A B', and run again.")
if MARKER_LABEL in css:
    sys.exit(f"ERROR: the CSS must not contain the marker text '{MARKER_LABEL}'.")

url = os.environ.get('CMPLZ_URL', '').strip()
if not url.startswith(('https://', 'http://')):
    sys.exit("ERROR: set CMPLZ_URL to the site URL, e.g. CMPLZ_URL=https://example.com/")
if url.startswith('http://') and os.environ.get('CMPLZ_ALLOW_HTTP') != '1':
    sys.exit("ERROR: CMPLZ_URL uses http://, so a wp-admin login would travel unencrypted. Use https://, "
             "or set CMPLZ_ALLOW_HTTP=1 for a local test site.")
if not url.endswith('/'):
    url += '/'
user = os.environ.get('CMPLZ_USER', '')
pw = os.environ.get('CMPLZ_PASS', '')

JS = r"""const page = await browser.getPage("cmplz_apply_css");
const SITE=__SITE__, USER=__USER__, PASS=__PASS__, CSS=__CSS__, LABEL=__LABEL__;
const MS='/* --- '+LABEL+' START --- */', ME='/* --- '+LABEL+' END --- */';
await page.goto(SITE+"wp-admin/",{waitUntil:"domcontentloaded"});
if(page.url().includes("wp-login")){
  if(!page.url().startsWith(SITE)){console.log("LOGIN_ORIGIN_MISMATCH: login page "+page.url()+" is not under "+SITE+"; credentials not sent (use the site's canonical host, with or without www, in CMPLZ_URL)");throw new Error("LOGIN_ORIGIN_MISMATCH");}
  if(!USER||!PASS){console.log("NOT_LOGGED_IN: log in to wp-admin in this dev-browser profile, or set CMPLZ_USER and CMPLZ_PASS");throw new Error("NOT_LOGGED_IN");}
  await page.fill("#user_login",USER);await page.fill("#user_pass",PASS);await page.click("#wp-submit");
  await page.waitForLoadState("domcontentloaded");
  if(page.url().includes("wp-login")){console.log("LOGIN_FAILED");throw new Error("LOGIN_FAILED");}
}
await page.goto(SITE+"wp-admin/customize.php",{waitUntil:"domcontentloaded"});
if(!page.url().includes("customize.php")){console.log("NOT_LOGGED_IN: customize.php redirected to "+page.url()+" (custom login URL or missing permission?)");throw new Error("NOT_LOGGED_IN");}
await page.waitForTimeout(9000);
const info=await page.evaluate((a)=>{
  const {ms,me,label}=a;
  if(!window.wp||!window.wp.customize) return {error:'NO_CUSTOMIZE: the Customizer did not load (block theme, missing customize capability, or a login / error page)'};
  // Additional CSS setting id is theme-namespaced: custom_css[<theme>]
  let id=null; wp.customize.each(s=>{ if(/^custom_css(\[|$)/.test(s.id)) id=s.id; });
  if(!id) return {error:'NO_CSS_SETTING'};
  const s=wp.customize(id); if(!s) return {error:'NO_SETTING_OBJ:'+id};
  // publishing would also push unsaved or scheduled changes that are not ours
  const st=wp.customize.state&&wp.customize.state('changesetStatus');
  const status=st?String(st.get()||''):'';
  const dirty=typeof wp.customize.dirtyValues==='function'?Object.keys(wp.customize.dirtyValues()):[];
  if(['draft','future','pending'].includes(status)||dirty.length)
    return {error:'PENDING_CHANGES: the Customizer holds other unpublished changes (status "'+status+'", dirty: '+dirty.join(', ')+'); publish or discard them first'};
  const prev=String(s.get()||'');
  const esc=t=>t.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  const cur=prev.replace(new RegExp(esc(ms)+'[\\s\\S]*?'+esc(me),'g'),'').trim();
  if(cur.includes(label)) return {error:'STALE_MARKER: a damaged "'+label+'" marker remains in '+id+'; nothing changed, clean it up by hand'};
  return {id, prev, cur};
}, {ms:MS,me:ME,label:LABEL});
if(info.error){console.log(info.error);throw new Error(info.error);}
const backup=await writeFile("cmplz-custom-css-backup-"+Date.now()+".css", info.prev);
console.log("backup:", backup);
const res=await page.evaluate((a)=>{
  const {id,cur,css,ms,me}=a;
  const next=(cur?cur+'\n\n':'')+ms+'\n'+css+'\n'+me;
  wp.customize(id).set(next);
  return 'OK id='+id+' new='+next.length;
}, {id:info.id,cur:info.cur,css:CSS,ms:MS,me:ME});
console.log("set:",res,"prev="+info.prev.length);
await page.waitForTimeout(2000);
const saved=await page.evaluate(()=>{const b=document.querySelector('#save'); if(b){b.disabled=false;b.click();return 'clicked';}return 'NO_SAVE_BTN';});
await page.waitForTimeout(7000);
const status=await page.evaluate(()=>{const b=document.querySelector('#save');return b?(b.value+' disabled='+b.disabled):'?';});
console.log("save:",saved,"| status:",status);
// gotcha #18: never trust the save response; read the front end back
await page.goto(SITE+"?cmplz_css_check="+Date.now(),{waitUntil:"domcontentloaded"});
const front=await page.evaluate((ms)=>{
  const el=document.getElementById('wp-custom-css');
  if(!el) return {styleTag:false};
  const t=el.textContent||'';
  let rules=-1; try{ rules=Array.from(el.sheet.cssRules).filter(r=>r.cssText.includes('cmplz')).length; }catch(e){}
  return {styleTag:true, marker:t.includes(ms), cmplzRules:rules,
    openComments:(t.match(/\/\*/g)||[]).length, closeComments:(t.match(/\*\//g)||[]).length};
}, MS);
console.log("front:", JSON.stringify(front));
if(!front.styleTag||!front.marker||front.cmplzRules<1||front.openComments!==front.closeComments)
  throw new Error("FRONT_CHECK_FAILED: the front end does not show the expected rules"+(front.styleTag?"; see gotchas #18 and #42":"; no #wp-custom-css tag (a CSS optimizer combining inline CSS? purge or exclude it), see also #42"));
"""

# single pass over the template, so a value that happens to contain a placeholder is never rescanned
values = {'SITE': url, 'USER': user, 'PASS': pw, 'LABEL': MARKER_LABEL, 'CSS': css}
print(re.sub(r'__(SITE|USER|PASS|LABEL|CSS)__', lambda m: json.dumps(values[m.group(1)]), JS))
