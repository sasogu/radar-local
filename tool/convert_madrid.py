#!/usr/bin/env python3
"""Convert the official Madrid radar CSV into Radar Local schema v1.

Usage: python3 tool/convert_madrid.py input.csv output.json
The input is downloaded manually from the URL documented in DATA_SOURCES.md.
"""
import csv
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path


def bearing(a_lat, a_lon, b_lat, b_lon):
    lat1, lat2 = math.radians(a_lat), math.radians(b_lat)
    dlon = math.radians(b_lon - a_lon)
    y = math.sin(dlon) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def coordinate(row, lat_key, lon_key):
    lat, lon = float(row[lat_key]), float(row[lon_key])
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ValueError('Invalid coordinate')
    return {'lat': lat, 'lon': lon}


def convert(source):
    records = []
    seen = set()
    for row in csv.DictReader(source, delimiter=';'):
        ident = row['Nº RADAR'].strip()
        if not ident or ident in seen:
            raise ValueError('Missing or duplicate radar ID')
        seen.add(ident)
        kind = row['Tipo'].strip().lower()
        if kind not in ('fijo', 'radar de tramo'):
            continue
        point = coordinate(row, 'Latitud', 'Longitud')
        item = {'id': f'madrid-{ident}', 'kind': 'fixed', 'start': point,
                'name': row['Ubicacion'].strip()[:200]}
        limit = row['Velocidad límite'].strip()
        if limit:
            item['speed_limit'] = int(limit)
        if kind == 'radar de tramo':
            start = coordinate(row, 'Latitud inicio tramo', 'Longitud inicio tramo')
            item['kind'] = 'section'
            item['start'] = start
            item['end'] = point
            item['direction'] = round(bearing(start['lat'], start['lon'], point['lat'], point['lon']), 2)
        records.append(item)
    return {'schema': 1,
            'source': 'Ayuntamiento de Madrid, radares fijos, CC BY 4.0',
            'updated_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            'radars': records}


def main():
    if len(sys.argv) != 3:
        raise SystemExit('Usage: convert_madrid.py input.csv output.json')
    with Path(sys.argv[1]).open(encoding='utf-8-sig', newline='') as source:
        dataset = convert(source)
    Path(sys.argv[2]).write_text(json.dumps(dataset, ensure_ascii=False, indent=2) + '\n',
                                   encoding='utf-8')
    print(f"Converted {len(dataset['radars'])} radars")


if __name__ == '__main__':
    main()
