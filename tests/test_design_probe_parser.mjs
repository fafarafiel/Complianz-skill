// Offline test of the Google Fonts family parser inside scripts/design-probe.js.
// The parser is cut out of the probe between its marker comments and run with Node's URL class.
// Usage: node tests/test_design_probe_parser.mjs   (run from the repository root)
import { readFileSync } from 'node:fs';

const src = readFileSync('scripts/design-probe.js', 'utf8');
const m = src.match(/\/\/ --- family parser[^\n]*\n([\s\S]*?)\/\/ --- end family parser ---/);
if (!m) { console.log('FAIL  parser markers not found in design-probe.js'); process.exit(1); }
const googleFamilies = new Function('location', `${m[1]}; return googleFamilies;`)({ href: 'https://example.test/' });

let failures = 0;
const check = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : `  got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`}`);
  if (!ok) failures++;
};

check('Elementor combined, URL-encoded link',
  googleFamilies('https://fonts.googleapis.com/css?family=Roboto%3A100%2C100italic%2C400%7CRoboto+Slab%3A400%2C700&display=swap&ver=6.5'),
  ['Roboto', 'Roboto Slab']);
check('css2 with several family parameters',
  googleFamilies('https://fonts.googleapis.com/css2?family=Nunito:wght@400;700&family=Open+Sans:ital,wght@0,400&display=swap'),
  ['Nunito', 'Open Sans']);
check('classic pipe-separated list',
  googleFamilies('https://fonts.googleapis.com/css?family=Lato:400,700|Merriweather'),
  ['Lato', 'Merriweather']);
check('protocol-relative link', googleFamilies('//fonts.googleapis.com/css?family=Poppins:600'), ['Poppins']);
check('malformed escape does not throw (kept literally)', googleFamilies('https://fonts.googleapis.com/css?family=Bad%ZZ'), ['Bad%ZZ']);
check('unparsable URL returns nothing', googleFamilies('http://[bad'), []);
check('no family parameter', googleFamilies('https://fonts.googleapis.com/css?display=swap'), []);

console.log(failures ? `\n${failures} check(s) FAILED` : '\nall checks passed');
process.exit(failures ? 1 : 0);
