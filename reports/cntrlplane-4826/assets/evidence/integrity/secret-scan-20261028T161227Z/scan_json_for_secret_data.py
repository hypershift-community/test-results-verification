#!/usr/bin/env python3
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
hits = []
parsed = 0
for path in root.rglob('*'):
    if not path.is_file() or path.name == 'index.html':
        continue
    if path.suffix.lower() not in {'.json'}:
        continue
    try:
        obj = json.loads(path.read_text(errors='replace'))
    except Exception:
        continue
    parsed += 1
    stack = [obj]
    while stack:
        value = stack.pop()
        if isinstance(value, dict):
            if value.get('kind') == 'Secret' and (value.get('data') or value.get('stringData')):
                hits.append(str(path))
            stack.extend(value.values())
        elif isinstance(value, list):
            stack.extend(value)
print(f'parsed_json_files={parsed}')
print(f'secret_objects_with_data={len(set(hits))}')
for hit in sorted(set(hits)):
    print(hit)
