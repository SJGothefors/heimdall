# Heimdall

A native, dark-mode iPhone field notebook for **iOS 27**. SwiftUI, Apple frameworks, no third-party runtime packages, backend, accounts, analytics, or runtime map requests.

[Portrait preview](Docs/Screenshots/map-portrait.png) · [Landscape preview](Docs/Screenshots/map-landscape.png).

## Included

- A bundled Sweden overview with vector geography, satellite imagery, and an interactive elevation mesh. It works on first launch in airplane mode.
- Independent **BLUE / RED / TAC** layers. Add points, draw lines and polygons by tapping vertices, name and annotate objects, hide layers, and delete individual objects.
- A **7S notebook** with Stund, Ställe, Styrka, Slag, Sysselsättning, Symbol and Sagesman. Save incomplete drafts, reopen/edit them, read plain text over a radio, mark them sent, and delete them. The app does not transmit radio messages.
- Photo and video capture into an app-private local vault, thumbnails, playback, and deletion. Media is not added to Photos, so Heimdall does not initiate iCloud Photos sync. Videos are limited to five minutes per clip.
- Opt-in foreground location, with accuracy and stale-fix handling. No track history.
- Device authentication, complete file protection, backup exclusions, app-switcher shielding, and screen-recording/mirroring shielding.
- Local folder import for more detailed maps in the documented format.
- Portrait and both landscape orientations, with compact landscape map controls and an adaptive media grid. Rotation preserves the active drawing and report editor.

## Run

### VS Code or Terminal

Keep **Xcode 27 installed** for Apple's iOS SDK and simulator. You can use VS Code as your editor; open the whole `heimdall` folder, then press **Cmd+Shift+B** to run the included **Run Heimdall in iPhone simulator** task. The optional [Swift extension](https://code.visualstudio.com/docs/languages/swift) adds Swift editing support. This is an Xcode project, so the included task uses `xcodebuild`; it does not use `swift build` or configure VS Code breakpoint debugging.

The same task works from any terminal in this folder:

```sh
python3 Scripts/run_simulator.py
```

It selects an installed iOS 27+ iPhone simulator, boots it, opens **Device Hub**, builds the app, and launches it. If Device Hub shows a device list, select the iPhone named in the terminal output. No Apple account or signing team is needed for this simulator workflow. Build errors remain visible in the terminal.

This command enables the existing **Debug simulator-only authentication bypass**, so previewing the interface does not require a simulated passcode. Use `python3 Scripts/run_simulator.py --authenticate` to exercise authentication, or `--device 'iPhone 18 Pro'` to choose a particular installed simulator. It preserves the simulator's local app data.

### Xcode

1. Open `Heimdall.xcodeproj` in **Xcode 27**.
2. Select the **Heimdall** scheme and an iPhone simulator running iOS 27.
3. Choose **Product > Run** (**Cmd+R**, or the triangle in the toolbar). The simulated iPhone appears in **Device Hub**, separately from the source editor. An empty editor saying “No Selection” is not the app screen. Xcode Cloud sign-in is not needed.
4. The normal Xcode launch requests device authentication. For simulator UI preview, add `--ui-testing` under **Product > Scheme > Edit Scheme > Run > Arguments > Arguments Passed On Launch**, or use the terminal command above.

For a **physical iPhone**, select your development team under Signing & Capabilities, change the bundle identifier if necessary, and select the connected device as the run destination. The iPhone must have a passcode configured. Camera and microphone permissions are requested only when used; location is opt-in.

The checked-in Xcode project is ready to open. If you add source files outside Xcode, regenerate it with `python3 Scripts/generate_project.py`. No XcodeGen, CocoaPods or package resolution is needed.

For simulator UI development only, the Debug build accepts `--ui-testing` as a launch argument to bypass device authentication. This code is excluded from Release builds **and all physical-device builds**. Normal builds never seed invented observations, reports or media.

## Map coverage and limits

The bundled package is approximately 2 MB and covers **55–70° N, 10–25° E**, including Sweden and adjacent geographical context. It is a genuine country overview, **not a field-ready detailed map**:

- Vector: Natural Earth **1:10 million scale**, major roads, rivers, lakes and selected settlements. “10m” in the dataset name does not mean ten-meter resolution.
- Photo: NASA Blue Marble **July 2004** satellite imagery, prepared at Web Mercator zoom 7. It is low resolution, historical imagery, not current aerial photography.
- 3D: a **129 × 257** grid sampled from Mapzen terrain tiles. Vertical relief is explicitly exaggerated **12×**. This is an overview viewer, not a line-of-sight, navigation, or measurement system. Draw/edit in 2D; saved annotations also appear in 3D.

Detailed nationwide street maps, contemporary aerial imagery and detailed terrain are **not included**. Provision appropriate licensed, current offline datasets before relying on the app in the field. Import currently supports the small, bounded format in [Docs/MAP_PACKS.md](Docs/MAP_PACKS.md), not arbitrary MBTiles, PMTiles, GeoTIFF or ATAK data packages. This renderer is intentionally an overview renderer, not a replacement for a streaming vector-tile engine at nationwide street-level scale.

The app is inspired by the requested ATAK/iTAK workflow but does not implement CoT, TAK servers, team networking, routing, or standardized military symbology. Coordinates are WGS 84 decimal degrees; a 7S place field also accepts manually entered grid references without validating or converting them.

## Structure

```text
Heimdall/
  App/               App lifecycle, privacy shield, navigation, theme
  Models/            Coordinates, annotations, maps, media, 7S reports
  Services/          Local persistence, map import, authentication, location, media
  Features/Map/      Offline 2D renderer, terrain viewer, drawing and layers
  Features/Reports/  Seven-field editor and radio-reading view
  Features/Media/    Native capture and local vault
  Features/Settings/ Device controls, map import and data credits
  Resources/Sweden/  Bundled map.json and photo.jpg
HeimdallTests/       Persistence, geometry, import and media tests
HeimdallUITests/     Map and report lifecycle UI tests
```

The journal is an atomic JSON file under Application Support. Large media files stay outside the journal. Failed writes are surfaced to the user; corrupt journals are preserved and cannot be silently overwritten. There is no custom encryption scheme. Security depends on the iPhone passcode, iOS Data Protection and the application sandbox. Read [Docs/SECURITY.md](Docs/SECURITY.md) for guarantees and limits.

## Build and test

```sh
xcodebuild -project Heimdall.xcodeproj -scheme Heimdall \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

See [Docs/TESTING.md](Docs/TESTING.md) for device acceptance checks. The simulator cannot validate a real camera, GNSS reception, passcode-protected storage while locked, or operation under field conditions.

## Rebuild the overview maps (optional, online build step)

The data is already included; this is **not** needed to build or run the app.

```sh
python3 -m venv .venv
.venv/bin/pip install Pillow==12.3.0 Shapely==2.1.2
.venv/bin/python Scripts/prepare_maps.py
```

The preparation script downloads only public cartographic source data. It never reads user journal/media files. Sources are cached in `/private/tmp/heimdall-map-sources`. See [Docs/DATA_SOURCES.md](Docs/DATA_SOURCES.md) for attribution and source URLs.
