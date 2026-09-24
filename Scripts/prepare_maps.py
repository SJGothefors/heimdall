#!/usr/bin/env python3
"""Build-time only. Prepare a small, real Sweden overview; never run in the app.

Requires Python, Pillow and Shapely. Downloads public Natural Earth, NASA GIBS
and Mapzen terrain data. Cached source files live outside the repository.
"""
import concurrent.futures
import io
import json
import math
from pathlib import Path
import urllib.request
import hashlib
from PIL import Image
from shapely.geometry import shape, box

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Heimdall/Resources/Sweden'
CACHE = Path('/private/tmp/heimdall-map-sources')
CACHE.mkdir(exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
WEST, SOUTH, EAST, NORTH = 10.0, 55.0, 25.0, 70.0
source_manifest = {}

def fetch(url):
    import hashlib
    path = CACHE / hashlib.sha256(url.encode()).hexdigest()
    if not path.exists():
        req = urllib.request.Request(url, headers={'User-Agent': 'Heimdall-map-preparation/1.0'})
        with urllib.request.urlopen(req, timeout=90) as response:
            data = response.read()
        path.write_bytes(data)
    data = path.read_bytes()
    source_manifest[url] = {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
    return data

def coord(p):
    return {'latitude': round(p[1], 6), 'longitude': round(p[0], 6)}

def paths(g):
    if g.is_empty:
        return []
    if g.geom_type == 'Polygon':
        return [[coord(p) for p in g.exterior.coords]] + [[coord(p) for p in r.coords] for r in g.interiors]
    if g.geom_type == 'LineString':
        return [[coord(p) for p in g.coords]]
    if hasattr(g, 'geoms'):
        return [p for part in g.geoms for p in paths(part)]
    return []

clip = box(WEST, SOUTH, EAST, NORTH)
features, places = [], []
base = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/'
for dataset, kind in [('ne_10m_admin_0_countries', 'land'), ('ne_10m_lakes', 'water'),
                      ('ne_10m_rivers_lake_centerlines', 'river'), ('ne_10m_roads', 'road')]:
    print('Preparing', dataset, flush=True)
    data = json.loads(fetch(base + dataset + '.geojson'))
    for f in data['features']:
        g = shape(f['geometry'])
        if not g.intersects(clip):
            continue
        g = g.intersection(clip).simplify(0.003, preserve_topology=True)
        pp = paths(g)
        if pp:
            features.append({'kind': kind, 'paths': pp})

data = json.loads(fetch(base + 'ne_10m_populated_places_simple.geojson'))
for f in data['features']:
    x, y = f['geometry']['coordinates'][:2]
    props = {k.lower(): v for k, v in f['properties'].items()}
    if WEST <= x <= EAST and SOUTH <= y <= NORTH:
        places.append({'name': props['name'], 'coordinate': coord([x, y]), 'population': int(props.get('pop_max', 0))})

def world(lon, lat):
    return ((lon + 180) / 360, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2)

left, top = world(WEST, NORTH)
right, bottom = world(EAST, SOUTH)

def mosaic(zoom, provider):
    n = 2 ** zoom
    x0, y0 = math.floor(left*n), math.floor(top*n)
    x1, y1 = math.ceil(right*n), math.ceil(bottom*n)
    result = Image.new('RGB', ((x1-x0)*256, (y1-y0)*256))
    def tile(pos):
        x, y = pos
        if provider == 'photo':
            url = f'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/BlueMarble_NextGeneration/default/2004-07-01/GoogleMapsCompatible_Level8/{zoom}/{y}/{x}.jpeg'
        else:
            url = f'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{zoom}/{x}/{y}.png'
        return x, y, Image.open(io.BytesIO(fetch(url))).convert('RGB')
    positions = [(x, y) for y in range(y0,y1) for x in range(x0,x1)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for x,y,img in pool.map(tile, positions):
            result.paste(img, ((x-x0)*256, (y-y0)*256))
    bounds = ((left*n-x0)*256, (top*n-y0)*256, (right*n-x0)*256, (bottom*n-y0)*256)
    return result, bounds

print('Preparing satellite mosaic', flush=True)
photo, bounds = mosaic(7, 'photo')
photo = photo.crop(tuple(round(v) for v in bounds))
photo.save(OUT/'photo.jpg', quality=88, optimize=True)
print('Preparing elevation grid', flush=True)
dem, bounds = mosaic(6, 'terrain')
cols, rows = 129, 257
values = []
for y in range(rows):
    for x in range(cols):
        px = min(dem.width-1, round(bounds[0] + x/(cols-1)*(bounds[2]-bounds[0])))
        py = min(dem.height-1, round(bounds[1] + y/(rows-1)*(bounds[3]-bounds[1])))
        r,g,b = dem.getpixel((px,py))
        values.append(round(r*256+g+b/256-32768))

pack = {'version': 1, 'name': 'Sweden overview', 'detail': 'Overview only · not for field navigation',
        'attribution': 'Natural Earth (public domain) · NASA Blue Marble, July 2004 · Mapzen terrain: USGS GMTED2010, NOAA ETOPO1, EU-DEM / Copernicus. See bundled data credits.',
        'bounds': {'west':WEST,'south':SOUTH,'east':EAST,'north':NORTH},
        'features':features,'places':places,
        'elevation':{'columns':cols,'rows':rows,'meters':values}}
(OUT/'map.json').write_text(json.dumps(pack, separators=(',',':')))
(ROOT/'Docs/DATA_MANIFEST.json').write_text(json.dumps({'sources': source_manifest,
    'outputs': {name: hashlib.sha256((OUT/name).read_bytes()).hexdigest() for name in ['map.json', 'photo.jpg']}}, indent=2, sort_keys=True))
print(f'Wrote {len(features)} vector features, {len(places)} places, {len(values)} elevation samples.', flush=True)
