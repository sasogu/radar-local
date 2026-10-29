#!/usr/bin/env python3
"""Convert the DGT PDF subset of Tachwire's ODbL es.json to Radar Local v1.

Input: https://tachwire.app/data/cameras/es.json
Tachwire links each DGT PDF radar to IGN/DGT coordinates. See DATA_SOURCES.md.
"""
import json
import math
import sys
from pathlib import Path


def point(item):
    lat, lon = item['lat'], item['lon']
    if not (27 <= lat <= 44 and -19 <= lon <= 5):
        raise ValueError(f'Coordinates outside Spain: {item["id"]}')
    return {'lat': lat, 'lon': lon}


def camera_name(item):
    road = item.get('road') or 'Via no identificada'
    pk = item.get('pk')
    return f'{road} PK {pk}' if pk is not None else road


def direction(item):
    bearing = item.get('bearing')
    if item.get('bothWays') or bearing is None:
        return None
    if not (0 <= bearing < 360):
        raise ValueError(f'Invalid bearing: {item["id"]}')
    return bearing


def convert(data):
    if data.get('schema') != 1 or data.get('country') != 'ES' or data.get('licence') != 'ODbL-1.0':
        raise ValueError('Unexpected source metadata')
    cameras = [x for x in data['cameras'] if x.get('source') == 'dgt-radars-pdf']
    if len(cameras) < 900:
        raise ValueError('Too few DGT camera records')
    radars = []
    sections = {}
    for item in cameras:
        kind = item['type']
        if kind == 'speed':
            radar = {'id': 'tachwire-' + item['id'], 'kind': 'fixed',
                     'start': point(item), 'name': camera_name(item)}
            heading = direction(item)
            if heading is not None:
                radar['direction'] = heading
            limit = item.get('limit')
            if limit is not None and 10 <= limit <= 180:
                radar['speed_limit'] = limit
            radars.append(radar)
        elif kind in ('section_start', 'section_end'):
            section_id = item.get('section')
            if not section_id:
                raise ValueError(f'Section without ID: {item["id"]}')
            sections.setdefault(section_id, {})[kind] = item
        else:
            raise ValueError(f'Unexpected camera type: {kind}')
    for section_id, pair in sections.items():
        if set(pair) != {'section_start', 'section_end'}:
            raise ValueError(f'Incomplete section: {section_id}')
        start, end = pair['section_start'], pair['section_end']
        if math.hypot(start['lat'] - end['lat'], start['lon'] - end['lon']) < 0.0001:
            raise ValueError(f'Section endpoints identical: {section_id}')
        radar = {'id': 'tachwire-' + section_id, 'kind': 'section',
                 'start': point(start), 'end': point(end), 'name': camera_name(start)}
        heading = direction(start)
        if heading is not None:
            radar['direction'] = heading
        limit = start.get('limit')
        if limit is not None and 10 <= limit <= 180:
            radar['speed_limit'] = limit
        radars.append(radar)
    if len({x['id'] for x in radars}) != len(radars):
        raise ValueError('Duplicate radar IDs')
    return {'schema': 1,
            'source': 'DGT 2026 via Tachwire/IGN, ODbL 1.0',
            'updated_at': data['generated'],
            'radars': radars}


def main():
    if len(sys.argv) != 3:
        raise SystemExit('Usage: convert_tachwire_dgt.py es.json output.json')
    data = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    result = convert(data)
    Path(sys.argv[2]).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"Converted {len(result['radars'])} DGT radars")


if __name__ == '__main__':
    main()
