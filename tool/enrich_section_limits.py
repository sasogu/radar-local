#!/usr/bin/env python3
"""Complete section radar limits from OpenStreetMap maxspeed tags.

Tachwire only publishes a limit for 45 of the 129 section radars. This tool
queries the OSM API around each section endpoint, picks the nearest main road
(maxspeed tags) and stores the value in a committed overlay that the refresh
pipeline applies on every merge. Results are never invented: ambiguous or
distant matches are skipped for manual review.

Usage:
    tool/enrich_section_limits.py [--dataset assets/data/spain-radars.json]
                                  [--overlay assets/data/section-limits-osm.json]
                                  [--dry-run] [--limit N]
"""
import argparse
import json
import math
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import section_limits

ROOT = Path(__file__).resolve().parents[1]
API = 'https://api.openstreetmap.org/api/0.6/map'
USER_AGENT = 'RadarLocalDatasetEnrichment/1.0 (section speed limits)'
MAIN_ROADS = {
    'motorway', 'trunk', 'primary', 'secondary', 'tertiary',
    'motorway_link', 'trunk_link', 'primary_link', 'secondary_link',
    'tertiary_link', 'unclassified',
}
EARTH_RADIUS = 6371000.0


def metres(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS * math.asin(min(1, math.sqrt(h)))


def local_xy(lat, lon, ref_lat):
    return lon * 111320 * math.cos(math.radians(ref_lat)), lat * 110540


def segment_distance(point, a, b):
    px, py = local_xy(point[0], point[1], point[0])
    ax, ay = local_xy(a[0], a[1], point[0])
    bx, by = local_xy(b[0], b[1], point[0])
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    t = 0 if length == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length))
    return math.hypot(px - (ax + dx * t), py - (ay + dy * t))


def parse_maxspeed(value):
    if not value:
        return None
    value = value.strip()
    if ';' in value or '/' in value:
        return None
    match = re.fullmatch(r'(\d{2,3})(?:\s*km/h)?', value, re.IGNORECASE)
    if not match:
        return None
    limit = int(match.group(1))
    return limit if 10 <= limit <= 180 else None


def road_key(name):
    return name.split(' PK ')[0].strip()


def fetch(lat, lon, delta=0.0012, attempts=3):
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


def candidates(xml, lat, lon):
    root = ET.fromstring(xml)
    nodes = {
        node.get('id'): (float(node.get('lat')), float(node.get('lon')))
        for node in root.findall('node')
    }
    found = []
    for way in root.findall('way'):
        tags = {tag.get('k'): tag.get('v') for tag in way.findall('tag')}
        highway = tags.get('highway')
        if highway not in MAIN_ROADS:
            continue
        limit = parse_maxspeed(tags.get('maxspeed'))
        if limit is None:
            continue
        coords = [nodes[ref.get('ref')] for ref in way.findall('nd') if ref.get('ref') in nodes]
        if len(coords) < 2:
            continue
        distance = min(
            segment_distance((lat, lon), a, b) for a, b in zip(coords, coords[1:])
        )
        refs = {
            part.strip()
            for ref in re.split(r'[;,]', tags.get('ref') or '')
            for part in ref.split()
        }
        found.append({
            'distance': distance,
            'limit': limit,
            'highway': highway,
            'refs': refs,
        })
    return found


def choose(found, road):
    if not found:
        return None
    matching = [item for item in found if road in item['refs']]
    pool = matching or found
    if not matching:
        pool = [item for item in pool if not item['highway'].endswith('_link')]
        if not pool:
            return None
    nearest = min(pool, key=lambda item: item['distance'])
    threshold = 100 if matching else 35
    if nearest['distance'] > threshold:
        return None
    close = [item for item in pool if item['distance'] <= nearest['distance'] + 5]
    limits = {item['limit'] for item in close}
    if len(limits) > 1:
        return None
    return nearest['limit']


def enrich(dataset, overlay, dry_run, max_items):
    pending = [
        radar for radar in dataset['radars']
        if radar.get('kind') == 'section'
        and radar.get('speed_limit') is None
        and radar['id'] not in overlay['limits']
    ]
    print(f'{len(pending)} sections without limit or cached value', file=sys.stderr)
    added = skipped = 0
    for index, radar in enumerate(pending[:max_items], start=1):
        road = road_key(radar.get('name', ''))
        result = None
        for key in ('start', 'end'):
            point = radar.get(key)
            if not point:
                continue
            try:
                found = candidates(fetch(point['lat'], point['lon']), point['lat'], point['lon'])
            except Exception as error:  # noqa: BLE001 - report and continue
                print(f'{radar["id"]}: query failed: {error}', file=sys.stderr)
                found = []
            result = choose(found, road)
            if result is not None:
                break
            time.sleep(1.2)
        if result is None:
            skipped += 1
            print(f'{radar["id"]} {radar.get("name", "")}: no safe match', file=sys.stderr)
        else:
            added += 1
            overlay['limits'][radar['id']] = result
            print(f'{radar["id"]} {radar.get("name", "")}: {result}', file=sys.stderr)
        if not dry_run and index % 10 == 0:
            write(overlay)
        time.sleep(1.2)
    return added, skipped


def write(overlay):
    overlay['updated_at'] = datetime.now(timezone.utc).isoformat(timespec='seconds')
    overlay['limits'] = dict(sorted(overlay['limits'].items()))
    section_limits.OVERLAY.write_text(
        json.dumps(overlay, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', default=str(ROOT / 'assets/data/spain-radars.json'))
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--limit', type=int, default=1000)
    args = parser.parse_args()
    dataset = json.loads(Path(args.dataset).read_text(encoding='utf-8'))
    try:
        overlay = section_limits.load()
    except FileNotFoundError:
        overlay = {
            'schema': 1,
            'source': 'OpenStreetMap maxspeed via API, ODbL 1.0',
            'updated_at': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            'limits': {},
        }
    added, skipped = enrich(dataset, overlay, args.dry_run, args.limit)
    if not args.dry_run:
        write(overlay)
        print(f'Wrote {section_limits.OVERLAY} ({added} added, {skipped} skipped)')
    else:
        print(f'Dry run: {added} would be added, {skipped} skipped')


if __name__ == '__main__':
    main()
