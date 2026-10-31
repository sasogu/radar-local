#!/usr/bin/env python3
"""Infer fixed radar travel directions from OpenStreetMap oneway roads.

SCT and Madrid sources do not publish a numeric bearing. For radars on oneway
carriageways (motorways, dual carriageways and oneway urban roads) the nearest
matching OSM way gives a reliable travel direction. Two-way roads, ambiguous
carriageways and explicitly both-way DGT radars are skipped.

The reviewed values are stored in a committed overlay that the refresh
pipeline applies on every merge.

Usage:
    tool/enrich_directions.py [--dataset assets/data/spain-radars.json]
                              [--dry-run] [--limit N]
"""
import argparse
import json
import math
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import directions

ROOT = Path(__file__).resolve().parents[1]
API = 'https://api.openstreetmap.org/api/0.6/map'
USER_AGENT = 'RadarLocalDatasetEnrichment/1.0 (radar directions)'
MAIN_ROADS = {
    'motorway', 'trunk', 'primary', 'secondary', 'tertiary',
    'unclassified', 'residential',
}
EARTH_RADIUS = 6371000.0


def metres(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS * math.asin(min(1, math.sqrt(h)))


def bearing(a, b):
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dlon = math.radians(b[1] - a[1])
    y = math.sin(dlon) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def bearing_diff(a, b):
    return abs((a - b + 540) % 360 - 180)


def local_xy(lat, lon, ref_lat):
    return lon * 111320 * math.cos(math.radians(ref_lat)), lat * 110540


def closest_on_segment(point, a, b):
    px, py = local_xy(point[0], point[1], point[0])
    ax, ay = local_xy(a[0], a[1], point[0])
    bx, by = local_xy(b[0], b[1], point[0])
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    t = 0 if length == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length))
    distance = math.hypot(px - (ax + dx * t), py - (ay + dy * t))
    return distance, t


def oneway_forward(tags):
    value = (tags.get('oneway') or '').strip().lower()
    if value in ('yes', 'true', '1'):
        return True
    if value in ('-1', 'reverse'):
        return False
    if value in ('no', 'false', '0'):
        return None
    if tags.get('highway') in ('motorway', 'motorway_link', 'trunk', 'trunk_link'):
        return True
    return None


def road_key(name):
    if ' PK ' in name:
        return name.split(' PK ')[0].strip()
    if ' P.K. ' in name:
        return name.split(' P.K. ')[0].strip()
    return name.split(',')[0].strip()


def normalize(value):
    value = unicodedata.normalize('NFKD', value or '')
    value = ''.join(ch for ch in value if not unicodedata.combining(ch))
    return re.sub(r'[^a-z0-9]+', ' ', value.lower()).strip()


def fetch(lat, lon, delta=0.0015, attempts=3):
    bbox = ','.join(str(round(v, 6)) for v in (lon - delta, lat - delta, lon + delta, lat + delta))
    url = f'{API}?bbox={bbox}'
    for attempt in range(attempts):
        request = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=40) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code == 429 or error.code >= 500:
                time.sleep(3 * (attempt + 1))
                continue
            raise
    raise RuntimeError(f'OSM API failed for {lat},{lon}')


def candidates(xml, lat, lon, road, radar_name):
    root = ET.fromstring(xml)
    nodes = {
        node.get('id'): (float(node.get('lat')), float(node.get('lon')))
        for node in root.findall('node')
    }
    found = []
    radar_name_norm = normalize(radar_name)
    for way in root.findall('way'):
        tags = {tag.get('k'): tag.get('v') for tag in way.findall('tag')}
        highway = tags.get('highway')
        if highway not in MAIN_ROADS or highway.endswith('_link'):
            continue
        forward = oneway_forward(tags)
        if forward is None:
            continue
        coords = [nodes[ref.get('ref')] for ref in way.findall('nd') if ref.get('ref') in nodes]
        if len(coords) < 2:
            continue
        best = None
        for a, b in zip(coords, coords[1:]):
            distance, t = closest_on_segment((lat, lon), a, b)
            if best is not None and distance >= best['distance']:
                continue
            ax, ay = local_xy(a[0], a[1], lat)
            bx, by = local_xy(b[0], b[1], lat)
            px, py = local_xy(lat, lon, lat)
            dx, dy = bx - ax, by - ay
            norm = math.hypot(dx, dy)
            if norm == 0:
                continue
            hx, hy = dx / norm, dy / norm
            if not forward:
                hx, hy = -hx, -hy
            ox, oy = px - (ax + dx * t), py - (ay + dy * t)
            best = {
                'distance': distance,
                'heading': bearing(a, b) if forward else bearing(b, a),
                'cross': hx * oy - hy * ox,
            }
        if best is None:
            continue
        refs = {
            part.strip().upper()
            for ref in re.split(r'[;,]', tags.get('ref') or '')
            for part in ref.split()
        }
        way_name = normalize(tags.get('name') or '')
        name_match = bool(way_name) and (way_name in radar_name_norm or radar_name_norm in way_name)
        found.append({
            'distance': best['distance'],
            'bearing': best['heading'],
            'cross': best['cross'],
            'ref_match': road.upper() in refs,
            'name_match': name_match,
            'highway': highway,
        })
    return found


def choose(found):
    if not found:
        return None
    matching = [item for item in found if item['ref_match'] or item['name_match']]
    pool = matching or found
    threshold = 45 if matching else 15
    nearest = min(pool, key=lambda item: item['distance'])
    if nearest['distance'] > threshold:
        return None
    if len(matching) > 1 and nearest['cross'] >= 0:
        # Several carriageways of the same road: only trust the one whose right
        # shoulder holds the radar. Right-hand traffic means negative cross.
        return None
    close = [item for item in pool if item['distance'] <= nearest['distance'] + 4]
    if len(close) > 1 and nearest['cross'] >= 0:
        for i, first in enumerate(close):
            for second in close[i + 1:]:
                if bearing_diff(first['bearing'], second['bearing']) > 45:
                    return None
    return round(nearest['bearing'], 1)


def write(overlay):
    overlay['updated_at'] = datetime.now(timezone.utc).isoformat(timespec='seconds')
    overlay['directions'] = dict(sorted(overlay['directions'].items()))
    directions.OVERLAY.write_text(
        json.dumps(overlay, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def enrich(dataset, overlay, dry_run, max_items):
    pending = [
        radar for radar in dataset['radars']
        if radar.get('kind') == 'fixed'
        and radar.get('direction') is None
        and radar['id'] not in overlay['directions']
        and radar['id'] not in overlay.get('skip', [])
    ]
    print(f'{len(pending)} fixed radars without direction or cached value', file=sys.stderr)
    added = skipped = 0
    for index, radar in enumerate(pending[:max_items], start=1):
        point = radar['start']
        road = road_key(radar.get('name', ''))
        try:
            found = candidates(
                fetch(point['lat'], point['lon']), point['lat'], point['lon'],
                road, radar.get('name', ''))
        except Exception as error:  # noqa: BLE001 - report and continue
            print(f'{radar["id"]}: query failed: {error}', file=sys.stderr)
            found = []
        result = choose(found)
        if result is None:
            skipped += 1
            print(f'{radar["id"]} {radar.get("name", "")[:50]}: no safe direction', file=sys.stderr)
        else:
            added += 1
            overlay['directions'][radar['id']] = result
            print(f'{radar["id"]} {radar.get("name", "")[:50]}: {result}', file=sys.stderr)
        if not dry_run and index % 10 == 0:
            write(overlay)
        time.sleep(1.2)
    return added, skipped


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', default=str(ROOT / 'assets/data/spain-radars.json'))
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--limit', type=int, default=1000)
    args = parser.parse_args()
    dataset = json.loads(Path(args.dataset).read_text(encoding='utf-8'))
    try:
        overlay = directions.load()
    except FileNotFoundError:
        overlay = {
            'schema': 1,
            'source': 'OpenStreetMap way geometry, ODbL 1.0',
            'updated_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            'directions': {},
        }
    added, skipped = enrich(dataset, overlay, args.dry_run, args.limit)
    if not args.dry_run:
        write(overlay)
        print(f'Wrote {directions.OVERLAY} ({added} added, {skipped} skipped)')
    else:
        print(f'Dry run: {added} would be added, {skipped} skipped')


if __name__ == '__main__':
    main()
