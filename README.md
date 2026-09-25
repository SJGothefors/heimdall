# Heimdall

A native, dark-mode iPhone field notebook for **iOS 27**. SwiftUI with MapLibre Native for offline maps and ZIPFoundation for map packages. No backend, accounts or analytics.

[Portrait preview](Docs/Screenshots/map-portrait.png) · [Landscape preview](Docs/Screenshots/map-landscape.png).

## Included

- **Gotland preconfigured**, with Stockholm, Uppland, Skåne and Jämtland stored on the phone. Load up to **two detailed regions together**, archive either independently, and toggle their coverage outlines in Layers. The Sweden overview remains available outside loaded regions.
- Independent **BLUE / RED / TAC** layers. Add points, draw lines and polygons by tapping vertices, name and annotate objects, hide layers, and delete individual objects.
- A **7S notebook** with Stund, Ställe, Styrka, Slag, Sysselsättning, Symbol and Sagesman. Save incomplete drafts, reopen/edit them, read plain text over a radio, mark them sent, and delete them. The app does not transmit radio messages.
- Photo and video capture into an app-private local vault, thumbnails, playback, and deletion. Media is not added to Photos, so Heimdall does not initiate iCloud Photos sync. Videos are limited to five minutes per clip.
- **MGRS coordinates**, optional manual own-position marker, and opt-in foreground GPS (off by default). Recording metadata distinguishes manual positions from GPS and preserves the position timestamp. No track history.
- **Operator callsign** in Device → Callsign, shown beside your blue GPS/manual position marker. Leave it empty to use the GPS/MANUAL label. The callsign is saved in the protected local journal.
- Device authentication, complete file protection, backup exclusions, app-switcher shielding, and screen-recording/mirroring shielding.
- Local ZIP import of standard Protomaps v4 PMTiles, with optional raster imagery.
- Voice 7S drafts with playback, capture time and position metadata. Swedish/English **on-device speech-to-text**, using Apple language models prepared explicitly in Device settings before going offline. Availability depends on the device and language. Recording and manual notes do not require a model.
- Portrait and both landscape orientations, a hamburger navigation menu, coordinates alongside the top map controls, and an adaptive media grid. Bottom map buttons sit just above the home gesture area. Rotation preserves the active drawing and report editor.

## Run

The regional data is already prepared in this workspace. The ZIPs total about **844 MB** and are excluded from Git because several exceed GitHub's file-size limit. On a fresh clone, prepare them once while online:

```sh
python3 Scripts/prepare_region.py --all
```

This downloads a checksum-pinned official PMTiles CLI and the public regional extracts. The build checks that all five packages exist; it never downloads them implicitly. Initial Swift package resolution also needs internet. Once installed, maps and recordings work offline.

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

The checked-in Xcode project is ready to open. If you add source files outside Xcode, regenerate it with `python3 Scripts/generate_project.py`. Xcode resolves the two pinned Swift packages; no XcodeGen or CocoaPods is needed.

For simulator UI development only, the Debug build accepts `--ui-testing` as a launch argument to bypass device authentication. This code is excluded from Release builds **and all physical-device builds**. Normal builds never seed invented observations, reports or media.

## Map coverage and limits

The regional packages contain Protomaps v4 vector tiles derived from OpenStreetMap, with roads, intersections, buildings and place names through **zoom 15**. Higher zooms enlarge this detail. Sources are dated **2026-09-24**. Regional extents are buffered rectangles, not exact administrative or historical province boundaries; the outlines show those package extents.

| Region | Stored ZIP |
| --- | ---: |
| Gotland (loaded initially) | 16 MB |
| Stockholm | 173 MB |
| Uppland | 176 MB |
| Skåne | 142 MB |
| Jämtland | 337 MB |

Loading expands a working copy in protected storage. Archiving removes that copy but keeps the bundled ZIP. Only two working copies can be loaded. PMTiles already compresses tiles, so ZIP archiving is not a large additional compression gain. MapLibre reads tiles on demand instead of loading the whole region into memory.

Outside loaded regions, the overview covers **55–70° N, 10–25° E**:

- Vector: Natural Earth **1:10 million** geography; not ten-meter resolution.
- Photo: NASA Blue Marble **July 2004**, a low-resolution historical overview. Detailed aerial imagery is **not included**; the package format accepts separately licensed raster PMTiles.
- 3D: a **129 × 257** elevation grid, relief exaggerated **12×**. It remains a terrain overview, not a measurement or line-of-sight tool. Detailed regional vectors do not add detailed elevation.

Map completeness and freshness depend on the sources. The app does not implement CoT, TAK servers, team networking, routing or standardized military symbology. Display coordinates use MGRS/WGS 84; manually entered 7S place descriptions remain free text. See [map packages](Docs/MAP_PACKS.md) and [data sources](Docs/DATA_SOURCES.md).

## Structure

```text
Heimdall/
  App/               App lifecycle, privacy shield, navigation, theme
  Models/            Coordinates, annotations, maps, media, 7S reports
  Services/          Storage, package import, location, authentication, recording, speech
  Features/Map/      Local MapLibre style, terrain viewer, drawing and layers
  Features/Reports/  Seven-field editor, voice attachments and radio-reading view
  Features/Media/    Native capture and local vault
  Features/Settings/ Device controls, map import and data credits
  Resources/Sweden/  Country overview, photo and elevation
  Resources/Maps/    Local region ZIPs, overview geometry and fonts
HeimdallTests/       Persistence, geometry, import and media tests
HeimdallUITests/     Map and report lifecycle UI tests
```

The journal is an atomic JSON file under Application Support. Large media files stay outside the journal. Failed writes are surfaced to the user; corrupt journals are preserved and cannot be silently overwritten. There is no custom encryption scheme. Security depends on the iPhone passcode, iOS Data Protection and the application sandbox. Read [Docs/SECURITY.md](Docs/SECURITY.md) for guarantees and limits.

## Build and test

```sh
xcodebuild -project Heimdall.xcodeproj -scheme Heimdall \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO \
  -collect-test-diagnostics never -parallel-testing-enabled NO test
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
