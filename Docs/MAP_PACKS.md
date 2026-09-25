# Offline regional map packages

**Gotland is loaded on first launch.** Stockholm, Uppland, Skåne and Jämtland are stored as ZIPs. Device → Offline map regions lets you load **two together**, show either, or archive one. Loading a third never silently evicts a region. Layers → Loaded map borders toggles coverage outlines in Vector, Photo and 3D.

Packages cover buffered rectangular extents, not exact province/county boundaries. Neighboring packages overlap intentionally. The outline marks the declared extent where the extracted tile pyramid supplies detail; whole tiles can extend slightly beyond it. The country overview stays available outside loaded coverage.

## Prepare the included regions

On a fresh clone, run while connected:

```sh
python3 Scripts/prepare_region.py --all
```

Use `--region gotland` to prepare one, `--force` to rebuild, or `--pmtiles /path/to/pmtiles` to use an installed CLI. All five are required for the default app build. `--all --check` checks presence without network access.

`Scripts/regions.json` pins each extent, focus point, data date, source URL and SHA-256 of the extracted PMTiles. The script downloads the official **go-pmtiles 1.31.2** release, verifies its published SHA-256, extracts zooms 0–15 and verifies the result against the catalog. Preparation failure leaves the previous ZIP intact. Public data and CLI downloads require no API key.

The ZIPs total about 844 MB. They are ignored by Git; source, catalog, fonts and the small country overview are tracked. Running the app does not download map data. An installed app contains all five ZIPs, so switching regions works in airplane mode.

## Import another package

Transfer its ZIP into **On My iPhone**, then choose **Device → Import map package**. Import validates and stores the archive; choose Load region to use it. Only these root-level files are allowed:

```text
region.zip
  manifest.json
  basemap.pmtiles
  imagery.pmtiles    (optional)
```

Example `manifest.json` (replace hashes with those of your actual files):

```json
{
  "version": 1,
  "id": "gotland",
  "name": "Gotland",
  "schema": "protomaps-v4",
  "bounds": {"west": 17.8, "south": 56.8, "east": 19.5, "north": 58.5},
  "focus": {"latitude": 57.6348, "longitude": 18.2948},
  "sourceDate": "2026-09-24T04:00:00Z",
  "attribution": "© OpenStreetMap contributors (ODbL) · Natural Earth · Protomaps",
  "sourceURL": "https://build.protomaps.com/20260924.pmtiles",
  "sha256": "0518eb573353b7c4990d1e10eb160d1270fa93d36376ace23da3f352743bbfd3"
}
```

- **Basemap:** PMTiles v3, MVT tiles, **Protomaps v4 schema**. Generic PMTiles using another schema, MBTiles, raw OSM PBF and Apple/Google Maps downloads are not interchangeable with this style.
- **Imagery:** optional PMTiles v3 containing PNG, JPEG or WebP raster tiles. Include `imagerySHA256` in the manifest when present. Supply legally licensed aerial data for the declared extent.
- Source URLs are provenance text, never fetched by the app. Styles and glyphs come from the app, not imported packages.
- IDs contain 1–60 lowercase ASCII letters, digits or hyphens. Bounds must be finite and within the supported Sweden envelope; focus must lie inside them.
- At most three regular ZIP entries, no folders, symlinks, duplicate names or traversal paths. Manifest ≤16 KiB; total uncompressed size ≤2 GB. CRC, byte counts, SHA-256, PMTiles v3 header/type/section offsets and zoom limits are checked before publishing a working copy.
- This is structural/integrity validation, **not authentication of a map provider** or proof that every internal tile is well-formed. Imported manifests and maps are not signed. Metadata does not establish map quality or freshness.

Imported archives and working copies use complete iOS file protection and backup exclusions. Staging is cleaned on the next successful journal load after interruption. Validation failure leaves loaded regions unchanged. Archiving/removing maps does not modify tactical layers, reports, voice recordings or media.

Old overview folders from earlier app builds can still be read for photo/elevation compatibility. New imports use the ZIP workflow above; the detailed vector renderer uses the fixed local style and PMTiles sources.
