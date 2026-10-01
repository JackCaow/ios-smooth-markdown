#!/usr/bin/env python3
"""Compare public Swift declarations and symbol identity after swift build."""
import argparse, difflib, json, platform, subprocess, tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--update', action='store_true')
args = parser.parse_args()
modules = root/'.build/debug/Modules'
if not modules.exists():
    raise SystemExit('Run swift build first')
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
rows = set()
with tempfile.TemporaryDirectory() as temporary:
    for module in ['SmoothMarkdownCore', 'SmoothMarkdown']:
        subprocess.run(['xcrun', 'swift', 'symbolgraph-extract', '-module-name', module,
            '-minimum-access-level', 'public', '-I', str(modules), '-sdk', sdk,
            '-target', platform.machine()+'-apple-macos14.0', '-output-dir', temporary], check=True)
    for path in Path(temporary).glob('*.symbols.json'):
        for symbol in json.loads(path.read_text()).get('symbols', []):
            identifier = symbol['identifier']['precise']
            # Imported protocol defaults (for example SwiftUI.View modifiers)
            # belong to the SDK, not this package's compatibility contract.
            origin = identifier.split('::SYNTHESIZED::', 1)[0]
            if '::SYNTHESIZED::' in identifier and not origin.startswith(('s:14SmoothMarkdown', 's:18SmoothMarkdownCore')):
                continue
            declaration = ''.join(fragment['spelling'] for fragment in symbol.get('declarationFragments', []))
            rows.add(identifier+' | '+declaration)
current = '\n'.join(sorted(rows))+'\n'
baseline = root/'api/public-swift.txt'
if args.update:
    baseline.write_text(current)
    print('Public Swift declaration baseline updated')
elif not baseline.exists() or baseline.read_text() != current:
    old = baseline.read_text().splitlines() if baseline.exists() else []
    print('\n'.join(difflib.unified_diff(old, current.splitlines(), fromfile='baseline', tofile='current')))
    raise SystemExit('Public API changed. Review compatibility before updating the baseline.')
else:
    print('Public Swift declarations match reviewed baseline')
