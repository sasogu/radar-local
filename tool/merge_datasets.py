#!/usr/bin/env python3
"""Merge validated Radar Local JSON datasets, rejecting duplicate IDs."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def merge(paths):
    radars = []
    names = []
    seen = set()
    for path in paths:
        data = json.loads(Path(path).read_text(encoding='utf-8'))
        if data['schema'] != 1:
            raise ValueError(f'Unsupported schema: {path}')
        names.append(data['source'])
        for item in data['radars']:
            if item['id'] in seen:
                raise ValueError(f'Duplicate radar ID: {item["id"]}')
            seen.add(item['id'])
            radars.append(item)
    return {'schema': 1, 'source': ' + '.join(names),
            'updated_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            'radars': radars}


def main():
    if len(sys.argv) < 4:
        raise SystemExit('Usage: merge_datasets.py output.json input1.json input2.json ...')
    dataset = merge(sys.argv[2:])
    Path(sys.argv[1]).write_text(json.dumps(dataset, ensure_ascii=False, indent=2) + '\n',
                                 encoding='utf-8')
    print(f"Merged {len(dataset['radars'])} radars")


if __name__ == '__main__':
    main()
