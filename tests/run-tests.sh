#!/usr/bin/env bash
# Run every offline test. Needs bash, curl, python3 and node; no WordPress site and no network.
# Usage: bash tests/run-tests.sh
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
RC=0
echo "## scripts/apply-banner-css.py"; node tests/test_apply_banner_css.mjs || RC=1
echo; echo "## scripts/verify.sh"; /bin/bash tests/test_verify.sh || RC=1
echo; echo "## scripts/run-design-probe.sh"; /bin/bash tests/test_run_design_probe.sh || RC=1
echo; echo "## scripts/design-probe.js (font family parser)"; node tests/test_design_probe_parser.mjs || RC=1
echo; echo "## syntax"
for f in scripts/*.sh tests/*.sh; do /bin/bash -n "$f" || { echo "syntax error: $f"; RC=1; }; done
python3 - <<'PY' || RC=1
import ast, pathlib
for p in pathlib.Path('scripts').glob('*.py'):
    ast.parse(p.read_text(encoding='utf-8'), filename=str(p))
print('python syntax OK')
PY
echo; [ "$RC" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $RC
