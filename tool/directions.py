#!/usr/bin/env python3
"""Apply reviewed OSM travel directions to fixed radars without a bearing.

Overlay format:
    {"schema": 1, "source": "...", "updated_at": "...",
     "directions": {"id": 123.4}, "skip": ["id-with-ambiguous-direction"]}
"""
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT / 'assets/data/osm-directions.json'


def load(path=OVERLAY):
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    if data.get('schema') != 1 or not isinstance(data.get('directions'), dict):
        raise ValueError(f'Invalid direction overlay: {path}')
    for key, value in data['directions'].items():
        if not isinstance(key, str) or not isinstance(value, (int, float)) or not 0 <= value < 360:
            raise ValueError(f'Invalid direction: {key}={value!r}')
    skip = data.setdefault('skip', [])
    if not isinstance(skip, list) or not all(isinstance(item, str) for item in skip):
        raise ValueError(f'Invalid direction skip list: {path}')
    return data


def apply(dataset, overlay):
    """Fill missing directions in place and return how many were added."""
    added = 0
    for radar in dataset['radars']:
        if radar.get('kind') != 'fixed' or radar.get('direction') is not None:
            continue
        direction = overlay['directions'].get(radar['id'])
        if direction is None:
            continue
        radar['direction'] = direction
        added += 1
    if added:
        tag = ', directions from OSM way geometry (ODbL 1.0)'
        if tag not in dataset['source']:
            dataset['source'] += tag
        dataset['updated_at'] = datetime.now(timezone.utc).isoformat(timespec='seconds')
    return added
