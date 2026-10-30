#!/usr/bin/env python3
"""Convert the DGT enforcement-camera subset of Tachwire's ODbL es.json to Radar Local v1.

Input: https://tachwire.app/data/cameras/es.json
Tachwire links the DGT "Equipos automaticos de deteccion de infracciones" PDF
(seatbelt/phone, red-light, solid-line and stop cameras) to IGN kilometre posts. See DATA_SOURCES.md.
"""
import json
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


# Tachwire's "other" holds the PDF's solid-line and stop-sign cameras.
KINDS = {'seatbelt_phone': 'phone', 'red_light': 'redLight', 'other': 'lineStop'}


def convert(data):
    if data.get('schema') != 1 or data.get('country') != 'ES' or data.get('licence') != 'ODbL-1.0':
        raise ValueError('Unexpected source metadata')
    cameras = [x for x in data['cameras'] if x.get('source') == 'dgt-equipos-pdf']
    if sum(x.get('type') == 'seatbelt_phone' for x in cameras) < 200:
        raise ValueError('Too few DGT enforcement camera records')
    radars = []
    for item in cameras:
        kind = KINDS.get(item.get('type'))
        if kind is None:
            raise ValueError(f'Unexpected camera type: {item.get("type")}')
        radar = {'id': 'tachwire-' + item['id'], 'kind': kind,
                 'start': point(item), 'name': camera_name(item)}
        heading = direction(item)
        if heading is not None:
            radar['direction'] = heading
        radars.append(radar)
    if len({x['id'] for x in radars}) != len(radars):
        raise ValueError('Duplicate radar IDs')
    return {'schema': 1,
            'source': 'DGT 2024 via Tachwire/IGN, ODbL 1.0',
            'updated_at': data['generated'],
            'radars': radars}


def main():
    if len(sys.argv) != 3:
        raise SystemExit('Usage: convert_tachwire_equipos.py es.json output.json')
    data = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    result = convert(data)
    Path(sys.argv[2]).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n',
                                 encoding='utf-8')
    print(f"Converted {len(result['radars'])} DGT enforcement cameras")


if __name__ == '__main__':
    main()
