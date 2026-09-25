# Performance

Offline maps avoid network latency, but still need disk reads, tile decoding, drawing and GPU memory. Package size on disk is not the same as memory use: MapLibre reads local PMTiles tiles as needed. The app keeps at most two detailed regions loaded.

## Where work is avoided

- **Map overlays:** `MapOverlayRenderer` keeps saved annotations, the unfinished drawing and own position in separate sources. Panning does not rebuild their geometry. A GPS update changes only the position source; adding a drawing vertex changes only the draft. Changed geometry uses native MapLibre features instead of a JSON encode/decode round trip. Layer switches change style visibility without rebuilding saved objects.
- **3D terrain:** `TerrainScene` creates its 129 × 257 mesh and texture once per map revision. Annotation and coverage changes update their own nodes and preserve the camera. SceneKit renders on demand, with the existing 30 fps target during movement.
- **Photos:** `LocalImageLoader` reads and decodes on a serial actor, away from the UI thread. ImageIO downsamples to the requested display size and applies orientation. `LocalPhoto` cancels obsolete requests and releases its image when it leaves the screen. There is no shared media cache. Original files are untouched. This follows Apple's [image downsampling guidance](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use).
- **Map preparation:** archive extraction and overview parsing already run outside the main actor. Loading a large region still takes time and needs free space for its extracted working copy.

These changes keep existing offline resource rules, file protection and write-before-publish behavior. They do not introduce delayed saves or network caching.

## Measurements — 2026-09-25

Debug build, Xcode 27, iPhone 18 Pro simulator on iOS 27. These are focused checks, **not physical-phone frame-rate or battery measurements**.

| Check | Result |
| --- | --- |
| Unchanged overlays, 2,000 synthetic points, two runs of 40 updates | Former JSON preparation: **15.7–17.6 ms/update**. Cached preparation: **under 0.01 ms/update**. No geometry updates submitted. |
| 4,032 × 3,024 JPEG with rotation metadata, requested at 1,008 pixels | Decoded to **756 × 1,008**, under **4 MiB** of pixel storage; file bytes unchanged. A full 4-byte-per-pixel decode would be about 46.5 MiB. This compares image buffers, not total app memory. |
| Terrain annotation/coverage changes | Mesh and material retain identity; camera position survives; removed overlays disappear. |

`RenderingPerformanceTests` retains the former unchanged-frame JSON preparation as a test-only benchmark. It checks behavior without a fragile timing threshold. The benchmark excludes tile rendering, SwiftUI layout, native source processing and GPU work. Run it using the [test command](TESTING.md) with `-only-testing:HeimdallTests/RenderingPerformanceTests`.

## What to profile on a phone

Use a signed Release build and synthetic data on the oldest supported test phone. In Instruments, inspect Time Profiler, animation hitches and Allocations while panning dense regional maps, editing thousands of annotations, switching 3D coverage and scrolling a populated media vault. Repeat after sustained use to expose thermal throttling. Record device, OS, dataset, cold/warm launch and peak memory; compare the same workload before and after changes.

The journal is still one JSON file, synchronously validated and atomically saved before success is shown. Large notebooks can pause during saves. A storage worker or database is a possible next step if device profiling identifies this as a bottleneck; it needs explicit ordering, interruption and failed-save tests. Map mode changes still create a renderer, and editing a saved annotation rebuilds the saved-object source. Those are further profiling targets, not reasons to promise a lag-free app.
