#!/usr/bin/env python3
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
for name in ['catalog','sample']:
 a=(root/f'contracts/{name}.json').read_bytes()
 b=(root/f'app/BabyCore/Sources/BabyCore/Resources/{name}.json').read_bytes()
 assert a==b, f'{name} drifted between server and Swift'
 json.loads(a)
print('Shared catalog and snapshot fixtures match')
