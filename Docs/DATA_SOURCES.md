# Regional vector maps

The five regional packages are extracted from the [Protomaps daily basemap](https://docs.protomaps.com/basemaps/downloads), `https://build.protomaps.com/20260924.pmtiles`, schema 4.15.2, data timestamp **2026-09-24T04:00:00Z**. They contain MVT vector tiles through zoom 15 in standard PMTiles v3 containers.

© [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), licensed under the [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Natural Earth data is public domain. The packages are regional extracts, not proprietary Apple or Google Maps caches. Extents and extracted-file hashes are recorded in `Scripts/regions.json`. Package boundaries represent buffered rectangular coverage, not official province boundaries.

[MapLibre Native](https://github.com/maplibre/maplibre-native) renders local PMTiles. [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) handles bounded ZIP extraction. Versions are pinned in the Xcode project and Package.resolved. Third-party licence notices are bundled in `Resources/Maps/Notices.txt`.

Noto Sans Regular glyphs (Unicode 0–511, covering Swedish and English labels) come from [Protomaps basemap assets](https://github.com/protomaps/basemaps-assets/tree/main/fonts). SIL Open Font License text is bundled in `Resources/Maps/Fonts/OFL.txt`. Additional alphabets are not currently bundled.

# Bundled Sweden overview data

Prepared 2026-09-24 by `Scripts/prepare_maps.py`. The derived map contains clipped/simplified vectors, a cropped Web Mercator satellite mosaic, and a sampled elevation grid. It is not endorsed by the data providers.

## Vectors

[Natural Earth](https://www.naturalearthdata.com/downloads/10m-cultural-vectors2/) 1:10 million: country polygons, lakes, rivers/lake centerlines, roads and populated places. Data is [public domain](https://www.naturalearthdata.com/about/terms-of-use/). The script reads [the Natural Earth source repository](https://github.com/nvkelso/natural-earth-vector/tree/master/geojson). Downloaded source bytes are hashed in `DATA_MANIFEST.json`; the upstream `master` branch may change if regenerated later.

## Imagery

[NASA Blue Marble: Next Generation](https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/), July 2004. Delivered by [NASA Global Imagery Browse Services](https://www.earthdata.nasa.gov/data/tools/gibs), `BlueMarble_NextGeneration`, date `2004-07-01`, `GoogleMapsCompatible_Level8`, downloaded at zoom 7. No provider logos or imagery endorsement are implied.

### Detailed aerial imagery — not yet included

The bundled photograph cannot resolve streets or buildings in Visby. Enlarging or sharpening it cannot add that information. The regional vector packages do not contain aerial imagery.

[Lantmäteriet Ortofoto Nedladdning](https://geotorget.lantmateriet.se/dokument/projects/ortofoto-nedladdning/released/2025.02/) supplies aerial photographs; its current product documentation describes 0.16 m and 0.4 m ground resolution, depending on coverage/year. Downloads are free, but require an account, an approved access application and acceptance of the provider's conditions. Access was not available during development, so these photographs have **not** been downloaded or bundled. An OpenAerialMap catalog search for the Gotland package extent on 2026-09-25 returned elevation data only, not aerial imagery.

To supply detailed Photo mode:

1. Apply for **Ortofoto Nedladdning** in [Geotorget](https://geotorget.lantmateriet.se/geodataprodukter/ortofoto-nedladdning-api) and obtain access for the intended use.
2. Download the approved Gotland/Visby imagery, retaining its acquisition date, coverage and applicable attribution/use terms. Keep credentials and source downloads outside the repository, for example under ignored `LocalData/`.
3. Prepare georeferenced Web Mercator raster tiles in `imagery.pmtiles`, with 256-pixel PNG/JPEG/WebP tiles through zoom 18 and a total region ZIP below the app's 2 GB limit. Use smaller coverage if necessary; do not claim full-region imagery from a city-only extract.
4. Include the imagery's SHA-256 and attribution in the region manifest, then import the ZIP using the [map package workflow](MAP_PACKS.md). Archive a previously loaded copy before loading its updated package.

The application already supports local raster PMTiles. Provider access and actual aerial source data remain prerequisites for improving Photo resolution; no account or network connection is needed on the phone after a package is prepared and imported.

## Elevation

[Mapzen / Tilezen terrain tiles](https://registry.opendata.aws/terrain-tiles/), Terrarium-encoded PNG tiles from the public `elevation-tiles-prod` bucket, zoom 6. Decoding: `R × 256 + G + B / 256 − 32768` meters. Resampled to a 129 × 257 grid.

Relevant source acknowledgements, following [Tilezen attribution](https://github.com/tilezen/joerd/blob/master/docs/attribution.md):

- Global GMTED2010 and SRTM terrain data courtesy of the U.S. Geological Survey.
- Global ETOPO1 terrain data courtesy of the U.S. National Oceanic and Atmospheric Administration.
- Europe terrain data produced using Copernicus data and information funded by the European Union — EU-DEM layers.
- Norway terrain data © Kartverket.
- ArcticDEM terrain DEMs were created from DigitalGlobe imagery and funded under National Science Foundation awards 1043681, 1559691, and 1542736.

The script changes sampling, clips the geographical extent, and quantizes elevations to whole meters. Displayed 3D relief is exaggerated 12×. These derived data must not be represented as an original or verified navigation product.
