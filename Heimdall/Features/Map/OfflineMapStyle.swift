import Foundation

@MainActor enum OfflineMapStyle {
    static func json(maps: MapRepository, photo: Bool) -> String {
        let resources = Bundle.main.resourceURL!
        var sources: [String: Any] = [
            "overview": [
                "type": "geojson", "data": resources.appendingPathComponent("Maps/overview.geojson").absoluteString,
            ],
            "objects": ["type": "geojson", "data": ["type": "FeatureCollection", "features": []]],
        ]
        var layers: [[String: Any]] = [
            ["id": "background", "type": "background", "paint": ["background-color": "#10232c"]]
        ]
        func add(
            _ id: String, _ type: String, _ source: String, _ paint: [String: Any], sourceLayer: String? = nil,
            filter: [Any]? = nil, minzoom: Double = 0, layout: [String: Any]? = nil
        ) {
            var layer: [String: Any] = ["id": id, "type": type, "source": source, "paint": paint, "minzoom": minzoom]
            if let sourceLayer { layer["source-layer"] = sourceLayer }
            if let filter { layer["filter"] = filter }
            if let layout { layer["layout"] = layout }
            layers.append(layer)
        }
        func kind(_ value: String) -> [Any] { ["==", ["get", "kind"], value] }
        let labelPaint: [String: Any] = ["text-color": "#f0f2ed", "text-halo-color": "#121c20", "text-halo-width": 1.5]
        let labelLayout: [String: Any] = [
            "text-field": ["get", "name"], "text-font": ["Noto Sans Regular"], "text-size": 12,
        ]
        add("overview-land", "fill", "overview", ["fill-color": "#263934"], filter: kind("land"))
        add("overview-water", "fill", "overview", ["fill-color": "#10232c"], filter: kind("water"))
        add(
            "overview-river", "line", "overview", ["line-color": "#315668", "line-width": 1], filter: kind("river"),
            minzoom: 6)
        add("overview-roads", "line", "overview", ["line-color": "#807b58", "line-width": 1], filter: kind("road"))
        if photo {
            let b = maps.package?.bounds ?? .sweden
            let imageURL =
                maps.isImported
                ? maps.files.importedMapDirectory.appendingPathComponent("photo.jpg")
                : resources.appendingPathComponent("Sweden/photo.jpg")
            sources["photo"] = [
                "type": "image", "url": imageURL.absoluteString,
                "coordinates": [[b.west, b.north], [b.east, b.north], [b.east, b.south], [b.west, b.south]],
            ]
            add("photo", "raster", "photo", ["raster-opacity": 0.9])
        }
        for region in maps.loadedRegions {
            let source = "region-" + region.id
            let url = maps.directory(for: region).appendingPathComponent("basemap.pmtiles")
            sources[source] = ["type": "vector", "url": "pmtiles://" + url.absoluteString]
            if !photo {
                add(source + "-land", "fill", source, ["fill-color": "#263934"], sourceLayer: "earth", minzoom: 8)
                add(
                    source + "-landuse", "fill", source,
                    [
                        "fill-color": [
                            "match", ["get", "kind"], ["forest", "wood"], "#203d2c", ["farmland", "farmyard"],
                            "#3b402e", ["residential", "commercial", "industrial"], "#343c40", "#2e3e35",
                        ]
                    ], sourceLayer: "landuse", minzoom: 10)
                add(
                    source + "-water", "fill", source, ["fill-color": "#102b3a"], sourceLayer: "water",
                    filter: ["==", ["geometry-type"], "Polygon"], minzoom: 8)
                add(
                    source + "-streams", "line", source, ["line-color": "#416b80", "line-width": 1.2],
                    sourceLayer: "water", filter: ["==", ["geometry-type"], "LineString"], minzoom: 12)
                add(
                    source + "-buildings", "fill", source, ["fill-color": "#626963", "fill-outline-color": "#8e9687"],
                    sourceLayer: "buildings", filter: ["==", ["geometry-type"], "Polygon"], minzoom: 14)
            } else if region.imagerySHA256 != nil {
                sources[source + "-photo"] = [
                    "type": "raster",
                    "url": "pmtiles://"
                        + maps.directory(for: region).appendingPathComponent("imagery.pmtiles").absoluteString,
                    "tileSize": 256,
                ]
                add(source + "-regional-photo", "raster", source + "-photo", ["raster-opacity": 1], minzoom: 8)
            }
            let roadWidth: [Any] = ["interpolate", ["linear"], ["zoom"], 10, 0.7, 13, 1.5, 16, 5, 19, 16]
            add(
                source + "-road-casing", "line", source,
                [
                    "line-color": "#131a1c",
                    "line-width": ["interpolate", ["linear"], ["zoom"], 10, 2, 13, 3, 16, 7, 19, 18],
                ], sourceLayer: "roads", minzoom: 10, layout: ["line-cap": "round", "line-join": "round"])
            add(
                source + "-roads", "line", source,
                [
                    "line-color": [
                        "match", ["get", "kind"], ["highway", "major_road"], "#e0c481", "minor_road", "#ccd0c8", "path",
                        "#94ad8a", "#979b99",
                    ], "line-width": roadWidth,
                ], sourceLayer: "roads", minzoom: 10, layout: ["line-cap": "round", "line-join": "round"])
            var streetLayout = labelLayout
            streetLayout["symbol-placement"] = "line"
            streetLayout["text-size"] = 11
            add(
                source + "-road-names", "symbol", source, labelPaint, sourceLayer: "roads", minzoom: 14,
                layout: streetLayout)
            add(
                source + "-places", "symbol", source, labelPaint, sourceLayer: "places", minzoom: 8, layout: labelLayout
            )
            add(
                source + "-poi-names", "symbol", source, labelPaint, sourceLayer: "pois", minzoom: 16,
                layout: labelLayout)
        }
        add("overview-labels", "symbol", "overview", labelPaint, filter: kind("place"), layout: labelLayout)
        let coverage = maps.loadedRegions.enumerated().map { index, region -> [String: Any] in
            let b = region.bounds
            return [
                "type": "Feature", "properties": ["name": region.name, "color": index == 0 ? "#f4bc68" : "#c0a2e6"],
                "geometry": [
                    "type": "Polygon",
                    "coordinates": [
                        [
                            [b.west, b.south], [b.east, b.south], [b.east, b.north], [b.west, b.north],
                            [b.west, b.south],
                        ]
                    ],
                ],
            ]
        }
        sources["coverage"] = ["type": "geojson", "data": ["type": "FeatureCollection", "features": coverage]]
        add(
            "coverage-outline", "line", "coverage",
            ["line-color": ["get", "color"], "line-width": 2, "line-dasharray": [4, 3], "line-opacity": 0.85])
        var coverageLayout = labelLayout
        coverageLayout["symbol-placement"] = "line"
        coverageLayout["text-size"] = 11
        add("coverage-labels", "symbol", "coverage", labelPaint, layout: coverageLayout)
        for (layer, color) in [("BLUE", "#5caeff"), ("RED", "#ff7079"), ("TAC", "#bfdb8c"), ("OWN", "#ffffff")] {
            let filter: [Any] = ["==", ["get", "layer"], layer]
            add(
                "area-" + layer, "fill", "objects", ["fill-color": color, "fill-opacity": 0.16],
                filter: ["all", filter, ["==", ["geometry-type"], "Polygon"]])
            add(
                "line-" + layer, "line", "objects", ["line-color": color, "line-width": 3],
                filter: ["all", filter, ["!=", ["geometry-type"], "Point"]])
            add(
                "point-" + layer, "circle", "objects",
                [
                    "circle-color": color, "circle-radius": layer == "OWN" ? 6 : 7, "circle-stroke-color": "#0c1112",
                    "circle-stroke-width": 2,
                ], filter: ["all", filter, ["==", ["geometry-type"], "Point"]])
            var layout = labelLayout
            layout["text-offset"] = [0, 1.5]
            layout["text-size"] = 12
            add(
                "label-" + layer, "symbol", "objects",
                ["text-color": color, "text-halo-color": "#0c1112", "text-halo-width": 2], filter: filter,
                layout: layout)
        }
        let style: [String: Any] = [
            "version": 8, "name": "Heimdall offline", "sources": sources, "layers": layers,
            "glyphs": resources.appendingPathComponent("Maps/Fonts").absoluteString + "/{fontstack}/{range}.pbf",
        ]
        let data = try! JSONSerialization.data(withJSONObject: style, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
