#!/usr/bin/env python3
"""Apply reviewed manual corrections to source radar data.

Overlay format:
    {"schema": 1, "source": "...", "updated_at": "...",
     "remove": ["id"], "override": {"id": {"start": {"lat": 1, "lon": 2}}}}

Only fields that a source can get wrong are accepted: coordinates, direction,
speed limit and name. Unknown fields are rejected to keep the review honest.
"""
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT / 'assets/data/radar-corrections.json'
ALLOWED = {'start', 'end', 'direction', 'speed_limit', 'name'}


def load(path=OVERLAY):
    data = json.loads(Path(path).read_text(encoding='utf-8'))
    if data.get('schema') != 1:
        raise ValueError(f'Invalid correction overlay: {path}')
    remove = data.setdefault('remove', [])
    override = data.setdefault('override', {})
    if not isinstance(remove, list) or not all(isinstance(item, str) for item in remove):
        raise ValueError(f'Invalid remove list: {path}')
    if not isinstance(override, dict):
        raise ValueError(f'Invalid override map: {path}')
    for key, fields in override.items():
        if not isinstance(fields, dict) or not set(fields) <= ALLOWED:
            raise ValueError(f'Invalid correction fields: {key}')
        for point in ('start', 'end'):
            value = fields.get(point)
            if value is None:
                continue
            if not isinstance(value, dict) or set(value) != {'lat', 'lon'}:
                raise ValueError(f'Invalid {point} point: {key}')
            if not (-90 <= value['lat'] <= 90 and -180 <= value['lon'] <= 180):
                raise ValueError(f'Invalid {point} coordinates: {key}')
    return data


def apply(dataset, overlay):
    """Apply removals and field overrides in place; return changed count."""
    removed = set(overlay['remove'])
    changed = 0
    radars = []
    for radar in dataset['radars']:
        if radar['id'] in removed:
            changed += 1
            continue
        fields = overlay['override'].get(radar['id'])
        if fields:
            radar.update(fields)
            changed += 1
        radars.append(radar)
    dataset['radars'] = radars
    if changed:
        tag = ', manual corrections'
        if tag not in dataset['source']:
            dataset['source'] += tag
        dataset['updated_at'] = datetime.now(timezone.utc).isoformat(timespec='seconds')
    return changed
