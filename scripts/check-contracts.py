#!/usr/bin/env python3
from pathlib import Path
import json,subprocess
root=Path(__file__).resolve().parents[1]
for name in ['catalog','sample','nara-import-sample','summary-cases','detail-cases','activity-payload']:
 a=(root/f'contracts/{name}.json').read_bytes()
 target='Sources/BabyCore' if name in ['catalog','sample'] else 'Tests/BabyCoreTests'
 b=(root/f'app/BabyCore/{target}/Resources/{name}.json').read_bytes()
 assert a==b, f'{name} drifted between server and Swift'
 json.loads(a)
for program in ['generate-catalog.py','generate-fixture.mjs','generate-summary-fixture.mjs','generate-detail-fixture.mjs','generate-activity-fixture.mjs']:
 subprocess.run(['python3' if program.endswith('.py') else 'node',str(root/'scripts'/program),'--check'],check=True,cwd=root)
print('Shared contracts match and their generators are current')
