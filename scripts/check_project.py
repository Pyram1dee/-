from pathlib import Path
root = Path(__file__).resolve().parents[1]
required = ['CLAUDE.md', 'README.md', 'docs/TECH_SPEC_RU.md', 'docs/IMPLEMENTATION_PLAN.md', 'source/cso_core.sma', 'config/plugins-cso.ini', 'tests/ACCEPTANCE.md']
missing = [p for p in required if not (root / p).is_file()]
if missing:
    raise SystemExit('Missing: ' + ', '.join(missing))
print('Project scaffold OK. This does NOT verify AMXX compilation or HLDS runtime.')
