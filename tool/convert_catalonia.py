#!/usr/bin/env python3
"""Convert SCT official ETRS89/UTM31 fixed-radar TXT to Radar Local JSON v1.

Requires PROJ's cs2cs command. Usage: python3 tool/convert_catalonia.py input.txt output.json
"""
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def convert(raw):
    rows = []
    skipped = 0
    for line in raw.splitlines()[3:]:
        if not line.strip():
            continue
        parts = line.split()
        if len(parts) < 5:
            raise ValueError(f'Unexpected line: {line!r}')
        road = ' '.join(parts[:-4])
        pk = parts[-4]
        speed = int(parts[-3])
        x = float(parts[-2].replace(',', '.'))
        y = float(parts[-1].replace(',', '.'))
        # PK ranges describe section radars; this source gives no reliable pair
        # of entrance/exit coordinates for them. Exclude them until verified.
        if not re.fullmatch(r'\d+(?:,\d+)?', pk) or not (100000 <= x <= 900000 and 4400000 <= y <= 4800000):
            skipped += 1
            continue
        if not road or not (10 <= speed <= 180):
            raise ValueError(f'Invalid radar: {line!r}')
        rows.append((road, pk, speed, x, y))
    coordinate_input = ''.join(f'{x} {y}\n' for _, _, _, x, y in rows)
    result = subprocess.run(['cs2cs', '-f', '%.8f', 'EPSG:25831', 'EPSG:4326'],
                            input=coordinate_input, text=True, capture_output=True, check=True)
    points = result.stdout.splitlines()
    if len(points) != len(rows):
        raise ValueError('Coordinate count mismatch')
    radars = []
    for i, ((road, pk, speed, _, _), point) in enumerate(zip(rows, points), 1):
        lat, lon = map(float, point.split()[:2])
        if not (40.4 <= lat <= 42.9 and 0 <= lon <= 3.5):
            raise ValueError(f'Coordinate outside Catalonia: {lat}, {lon}')
        radars.append({'id': f'sct-{i}', 'kind': 'fixed',
                       'start': {'lat': lat, 'lon': lon},
                       'speed_limit': speed, 'name': f'{road} PK {pk}'})
    if skipped > 50:
        raise ValueError(f'Too many unverified rows: {skipped}')
    print(f'Skipped {skipped} section/invalid-coordinate rows', file=sys.stderr)
    return {'schema': 1,
            'source': 'Servei Català de Trànsit, radars fixos, reutilització amb atribució',
            'updated_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            'radars': radars}


def main():
    if len(sys.argv) != 3:
        raise SystemExit('Usage: convert_catalonia.py input.txt output.json')
    data = convert(Path(sys.argv[1]).read_text(encoding='utf-8'))
    Path(sys.argv[2]).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n',
                                   encoding='utf-8')
    print(f"Converted {len(data['radars'])} radars")


if __name__ == '__main__':
    main()
