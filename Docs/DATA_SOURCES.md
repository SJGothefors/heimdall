# Bundled Sweden overview data

Prepared 2026-09-24 by `Scripts/prepare_maps.py`. The derived map contains clipped/simplified vectors, a cropped Web Mercator satellite mosaic, and a sampled elevation grid. It is not endorsed by the data providers.

## Vectors

[Natural Earth](https://www.naturalearthdata.com/downloads/10m-cultural-vectors2/) 1:10 million: country polygons, lakes, rivers/lake centerlines, roads and populated places. Data is [public domain](https://www.naturalearthdata.com/about/terms-of-use/). The script reads [the Natural Earth source repository](https://github.com/nvkelso/natural-earth-vector/tree/master/geojson). Downloaded source bytes are hashed in `DATA_MANIFEST.json`; the upstream `master` branch may change if regenerated later.

## Imagery

[NASA Blue Marble: Next Generation](https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/), July 2004. Delivered by [NASA Global Imagery Browse Services](https://www.earthdata.nasa.gov/data/tools/gibs), `BlueMarble_NextGeneration`, date `2004-07-01`, `GoogleMapsCompatible_Level8`, downloaded at zoom 7. No provider logos or imagery endorsement are implied.

## Elevation

[Mapzen / Tilezen terrain tiles](https://registry.opendata.aws/terrain-tiles/), Terrarium-encoded PNG tiles from the public `elevation-tiles-prod` bucket, zoom 6. Decoding: `R × 256 + G + B / 256 − 32768` meters. Resampled to a 129 × 257 grid.

Relevant source acknowledgements, following [Tilezen attribution](https://github.com/tilezen/joerd/blob/master/docs/attribution.md):

- Global GMTED2010 and SRTM terrain data courtesy of the U.S. Geological Survey.
- Global ETOPO1 terrain data courtesy of the U.S. National Oceanic and Atmospheric Administration.
- Europe terrain data produced using Copernicus data and information funded by the European Union — EU-DEM layers.
- Norway terrain data © Kartverket.
- ArcticDEM terrain DEMs were created from DigitalGlobe imagery and funded under National Science Foundation awards 1043681, 1559691, and 1542736.

The script changes sampling, clips the geographical extent, and quantizes elevations to whole meters. Displayed 3D relief is exaggerated 12×. These derived data must not be represented as an original or verified navigation product.
