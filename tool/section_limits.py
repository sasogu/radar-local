#!/usr/bin/env python3
"""Apply reviewed OSM maxspeed values to section radars that lack a limit.

Tachwire only publishes a limit for 45 of the 129 section radars. This module
keeps the reviewed values in a small committed overlay so the daily refresh
does not lose them when it rebuilds the merged dataset.

Overlay format:
    {"schema": 1, "source": "...", "updated_at": "...", "limits": {"id": 120}}
"""
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT / 'assets/data/section-limits-osm.json'


def load(path=OVERLAY):
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    if data.get('schema') != 1 or not isinstance(data.get('limits'), dict):
        raise ValueError(f'Invalid section limit overlay: {path}')
    for key, value in data['limits'].items():
        if not isinstance(key, str) or not isinstance(value, int) or not 10 <= value <= 180:
            raise ValueError(f'Invalid section limit: {key}={value!r}')
    return data


def apply(dataset, overlay):
    """Fill missing limits in place and return how many were added."""
    limits = overlay['limits']
    added = 0
    for radar in dataset['radars']:
        if radar.get('kind') != 'section' or radar.get('speed_limit') is not None:
            continue
        limit = limits.get(radar['id'])
        if limit is None:
            continue
        radar['speed_limit'] = limit
        added += 1
    if added:
        tag = ', section limits from OSM maxspeed (ODbL 1.0)'
        if tag not in dataset['source']:
            dataset['source'] += tag
        dataset['updated_at'] = datetime.now(timezone.utc).isoformat(
            timespec='seconds')
    return added
