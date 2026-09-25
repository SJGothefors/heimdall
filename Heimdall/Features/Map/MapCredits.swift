import SwiftUI

struct MapCredits: View {
    let maps: MapRepository
    var body: some View {
        List {
            Section("Detailed regions") {
                Text(
                    "These packages contain Protomaps v4 vector tiles from OpenStreetMap, including roads, intersections, buildings and place names, through zoom 15. Zooming further enlarges that detail. Coverage depends on OpenStreetMap contributors; it is not a surveyed or certified tactical map."
                )
                Text(
                    "© OpenStreetMap contributors · openstreetmap.org/copyright · ODbL. Natural Earth: public domain. Protomaps basemap."
                )
                ForEach(maps.loadedRegions) { region in
                    Text(region.attribution)
                    Text("Data: \(region.sourceDate)")
                    Text(region.sourceURL).font(.caption).textSelection(.enabled)
                }
            }
            Section("Photo & 3D") {
                Text(
                    "The bundled photo is NASA Blue Marble, July 2004: a country overview, not detailed aerial imagery. A region ZIP can include a separately licensed raster imagery.pmtiles file for high-resolution Photo mode."
                )
                Text(
                    "3D is the bundled elevation overview, exaggerated 12×. It is not a measurement or line-of-sight tool."
                )
            }
            Section("Sweden overview") {
                Text(
                    "Natural Earth 1:10 million geography. NASA Earth Observatory Blue Marble. Terrain: Mapzen / Tilezen, USGS GMTED2010 and SRTM, NOAA ETOPO1, EU Copernicus EU-DEM, © Kartverket, and ArcticDEM (NSF awards 1043681, 1559691, 1542736)."
                )
            }
            Section("Package format") {
                Text(
                    "ZIP containing manifest.json, a standard Protomaps v4 basemap.pmtiles, and optional imagery.pmtiles. Package structure, bounds and file hashes are checked. Transfer additional packages into Files before offline import."
                )
                Text(
                    "MapLibre Native renders the map. Noto Sans is licensed under the SIL Open Font License. All styles and fonts are stored locally."
                )
            }
        }.font(.subheadline).scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Map credits").navigationBarTitleDisplayMode(.inline)
    }
}
