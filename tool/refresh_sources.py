#!/usr/bin/env python3
"""Prepare reviewable radar JSON changes from current upstream sources."""
import argparse
import io
import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import convert_catalonia
import convert_madrid
import convert_tachwire_dgt
import merge_datasets

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'assets/data'
SOURCES = {
    'dgt': 'https://tachwire.app/data/cameras/es.json',
    'catalonia': 'https://transit.gencat.cat/web/.content/documents/seguretat_viaria/radars.txt',
    'madrid': 'https://datos.madrid.es/dataset/300049-0-radares-fijos-moviles/resource/300049-1-radares-fijos-moviles-csv/download/300049-1-radares-fijos-moviles-csv.csv',
}


def download(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'RadarLocalRefresh/1.0'})
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.url.split(':', 1)[0] != 'https':
            raise ValueError('Insecure redirect')
        raw = response.read(25 * 1024 * 1024 + 1)
    if len(raw) > 25 * 1024 * 1024 or len(raw) < 100:
        raise ValueError('Unexpected source size')
    return raw


def validate(name, data):
    if data['schema'] != 1 or not isinstance(data['radars'], list):
        raise ValueError(f'{name}: invalid schema')
    previous = json.loads((DATA / f'{name}-radars.json').read_text())
    count = len(data['radars'])
    if not (len(previous['radars']) * 0.8 <= count <= len(previous['radars']) * 1.3):
        raise ValueError(f'{name}: suspicious radar count {count}')
    ids = [item['id'] for item in data['radars']]
    if len(set(ids)) != len(ids):
        raise ValueError(f'{name}: duplicate radar IDs')
    return previous


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    updates = {
        'dgt': convert_tachwire_dgt.convert(json.loads(download(SOURCES['dgt']))),
        'catalonia': convert_catalonia.convert(download(SOURCES['catalonia']).decode('utf-8-sig')),
        'madrid': convert_madrid.convert(
            io.StringIO(download(SOURCES['madrid']).decode('utf-8-sig'))),
    }
    changed = []
    for name, data in updates.items():
        previous = validate(name, data)
        if data['radars'] != previous['radars']:
            changed.append(name)
            if not args.dry_run:
                (DATA / f'{name}-radars.json').write_text(
                    json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    if changed and not args.dry_run:
        merged = merge_datasets.merge([
            DATA / 'dgt-radars.json', DATA / 'catalonia-radars.json',
            DATA / 'madrid-radars.json',
        ])
        (DATA / 'spain-radars.json').write_text(
            json.dumps(merged, ensure_ascii=False, indent=2) + '\n')
    print('Changed sources: ' + (', '.join(changed) or 'none'))


if __name__ == '__main__':
    main()
