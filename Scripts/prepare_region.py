#!/usr/bin/env python3
"""Prepare the app's pinned, public offline map packages. Requires internet."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CATALOG = json.loads((ROOT / 'Scripts/regions.json').read_text())
OUTPUT = ROOT / 'Heimdall/Resources/Maps'
CLI_VERSION = '1.31.2'
CLI_HASHES = {
    'arm64': '40528f7f616fcbf91207cd48c8fc023d213f6d86c0cbf1f748732803d1880f3d',
    'x86_64': '1f0dc02eee6c58312dd6c509faee1b5c32f0596568af1bf51f1b034e7a88a65b',
}


def download_cli(directory):
    architecture = platform.machine()
    if platform.system() != 'Darwin' or architecture not in CLI_HASHES:
        raise RuntimeError('Provide --pmtiles /path/to/pmtiles on this platform.')
    name = f'go-pmtiles-{CLI_VERSION}_Darwin_{architecture}.zip'
    url = f'https://github.com/protomaps/go-pmtiles/releases/download/v{CLI_VERSION}/{name}'
    archive_path = directory / name
    print(f'Downloading official PMTiles CLI {CLI_VERSION}…', flush=True)
    urllib.request.urlretrieve(url, archive_path)
    with archive_path.open('rb') as file:
        if hashlib.file_digest(file, 'sha256').hexdigest() != CLI_HASHES[architecture]:
            raise RuntimeError('PMTiles CLI checksum does not match the pinned release.')
    executable = directory / 'pmtiles'
    with zipfile.ZipFile(archive_path) as archive:
        executable.write_bytes(archive.read('pmtiles'))
    executable.chmod(0o700)
    return str(executable)


def prepare(manifest, executable, directory):
    destination = OUTPUT / (manifest['id'] + '.zip')
    tiles = directory / (manifest['id'] + '.pmtiles')
    bounds = manifest['bounds']
    bbox = ','.join(str(bounds[key]) for key in ['west', 'south', 'east', 'north'])
    subprocess.run([executable, 'extract', manifest['sourceURL'], str(tiles),
                    '--bbox=' + bbox, '--maxzoom=15'], check=True)
    with tiles.open('rb') as file:
        if hashlib.file_digest(file, 'sha256').hexdigest() != manifest['sha256']:
            raise RuntimeError(f"{manifest['name']}: source data differs from the pinned extract.")
    # Publish only a complete archive; an interrupted download leaves the old one intact.
    staged = directory / destination.name
    with zipfile.ZipFile(staged, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False, indent=2))
        archive.write(tiles, 'basemap.pmtiles')
    os.replace(staged, destination)
    tiles.unlink()
    print(f"{manifest['name']}: {destination.stat().st_size:,} bytes", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument('--region', choices=[item['id'] for item in CATALOG], default='gotland')
    selection.add_argument('--all', action='store_true', help='Prepare all five regions for a full app build')
    parser.add_argument('--pmtiles', help='Use an installed PMTiles CLI instead of downloading the pinned release')
    parser.add_argument('--force', action='store_true', help='Rebuild existing archives')
    parser.add_argument('--check', action='store_true', help='Only check that selected packages are present')
    args = parser.parse_args()
    selected = [item for item in CATALOG if args.all or item['id'] == args.region]
    missing = [item for item in selected if not (OUTPUT / (item['id'] + '.zip')).is_file()]
    if args.check:
        if missing:
            parser.exit(1, 'Missing map packages. Run: python3 Scripts/prepare_region.py --all\n')
        print('Map packages are ready.')
        return
    selected = selected if args.force else missing
    if not selected:
        print('Map packages are already prepared. Use --force to rebuild.')
        return
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Staging on the same volume lets os.replace publish each ZIP atomically.
    with tempfile.TemporaryDirectory(prefix='.map-prepare-', dir=OUTPUT) as temporary:
        directory = Path(temporary)
        executable = args.pmtiles or download_cli(directory)
        for manifest in selected:
            prepare(manifest, executable, directory)


if __name__ == '__main__':
    main()
