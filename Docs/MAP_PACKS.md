# Local map packages, version 1

Choose **Device → Import local map folder** and select a folder already on the phone. Two files are copied; additional files are ignored:

```text
MySwedenMap/
  map.json
  photo.jpg
```

Use the bundled `Heimdall/Resources/Sweden` as a complete working example. Coordinates are WGS 84 decimal degrees. The photo and elevation grid must cover **exactly the manifest bounds**, projected in **Web Mercator (EPSG:3857)**, north at the top. Do not supply an unprojected latitude/longitude raster.

```json
{
  "version": 1,
  "name": "My regional map",
  "detail": "Source, date and practical resolution",
  "attribution": "Required data attribution and licence notices",
  "bounds": {"west": 15, "south": 59, "east": 16, "north": 60},
  "features": [
    {
      "kind": "land",
      "paths": [[
        {"latitude": 59, "longitude": 15},
        {"latitude": 60, "longitude": 15},
        {"latitude": 60, "longitude": 16},
        {"latitude": 59, "longitude": 16},
        {"latitude": 59, "longitude": 15}
      ]]
    }
  ],
  "places": [{"name": "Example", "coordinate": {"latitude": 59.5, "longitude": 15.5}, "population": 100}],
  "elevation": {"columns": 2, "rows": 2, "meters": [100, 110, 90, 105]}
}
```

Supported feature kinds: `land`, `water`, `river`, `road`. Each path is an ordered coordinate array; land/water use even-odd polygon filling, including holes. Lines are stroked. All geometry must lie within the package bounds. Elevation samples are row-major from the northwest, equally spaced **in projected coordinates**, in meters above sea level. Negative values are permitted but rendered at sea level in the terrain viewer.

Validation limits:

- Bounds within 9–26° E and 54–71° N, increasing and finite. The annotation workspace is 10–25° E and 55–70° N.
- `map.json`: 40 MB; `photo.jpg`: 32 MB.
- Image dimensions at most 8192 per side and 24 million pixels total.
- Up to 30,000 features, 300,000 total vertices, 10,000 places.
- Elevation: 2–512 columns and rows; sample count must match exactly; finite heights from −12,000 to 10,000 meters.
- Local regular files only; symlinks rejected. Filenames are fixed and no remote URLs, scripts or style expressions are interpreted.

Validation happens before replacing the current pack. Imported data is protected and excluded from backups. **Use bundled Sweden overview** restores the built-in map without touching annotations, reports or media. A regional import replaces the active basemap; it does not imply coverage outside its bounds. Source quality, freshness and authenticity remain the provider's responsibility. There is no digital signature or trust authority for imported packs.

This simple format is intended for modest country overviews and bounded regional detail. It does not support a multi-gigabyte tiled national map. For that scale, introduce an offline tile engine and a carefully provisioned package format rather than increasing these in-memory limits.
