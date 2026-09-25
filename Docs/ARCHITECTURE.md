# Architecture

Heimdall is a single-process SwiftUI app. Views edit local drafts and call services; models define what can be stored. There is no server, sync engine or background upload queue.

## Ownership and lifecycle

`AppRoot` owns `DeviceSecurity`, `LocalStore`, `MapRepository` and `LocationService`. It authenticates before opening the notebook, loads the journal, then prepares maps. Loading failure shows an error instead of replacing the journal with an empty one.

`MainView` owns navigation. Feature views receive the services they need. The map view stays mounted when switching sections so its camera and unfinished drawing survive navigation. Editors hold draft values until Save. These view drafts are temporary and may be lost when the authenticated view is removed.

`DeviceSecurity` uses device-owner authentication through `LAContext`. Backgrounding, manual lock and detected screen capture lock the app; backgrounding and lock stop location updates. Inactive scenes are covered by `PrivacyShield`, a separate window above sheets and the camera picker. File accessibility under iOS Data Protection follows the **device's lock state**, not the app's lock button. Objects already loaded in memory are not explicitly erased.

Most app state is isolated to the main actor. `MediaVault` and `LocalImageLoader` are actors; map parsing and extraction run in detached tasks. `MapRepository.isLoading` serializes user-initiated imports and region changes. The journal has one writer, `LocalStore`; adding another process or writer would require a different concurrency design.

## Saving and deleting

`FieldJournal` is the Codable schema and validation boundary. `LocalStore.commit` copies the current journal, applies a change, validates the complete result, encodes it, and writes it before publishing new state to SwiftUI. All edits use this path, including callsign and manual-position changes.

`SecureFiles.write` creates a sibling temporary file with complete protection, excludes it from backup, synchronizes its contents, then atomically renames it over the destination. Protection setup can fail before replacement; later cleanup errors cannot turn a published write into a reported save failure. This prevents a reported write failure from concealing a committed journal change. Atomic replacement protects against partial JSON, not every possible storage or hardware failure.

Attachments are separate files. Capture writes the file before adding its journal entry. A failed media entry save discards the new vault files; a voice save failure keeps the recording and offers retry while its recorder view exists. A process kill can still leave an unindexed or incomplete recording. There is no recovery browser, and unknown attachments are deliberately not swept away.

Deletion uses a small persistent queue:

1. Commit removal of the journal entry together with UUID-derived attachment paths in `pendingDeletions`.
2. Remove those files, accepting files already removed by an earlier attempt.
3. Commit removal of the completed queue.

If the first commit fails, no attachment is touched. A later failure leaves cleanup retryable after relaunch or in Device settings. A cleanup warning means the entry has gone from the notebook but bytes may remain. Validation forbids deleting any attachment still referenced by a retained entry and forbids sharing one voice file between reports.

## Storage layout

Writable app data lives under `Library/Application Support/Heimdall/` inside the app container:

| Path | Contents |
| --- | --- |
| `journal.json` | Annotations, media index, reports, transcripts, manual position, callsign, pending deletions |
| `Media/` | UUID-named JPEG/MOV captures and JPEG thumbnails |
| `Voice/` | UUID-named M4A voice recordings |
| `MapPacks/` | Imported regional ZIPs |
| `LoadedRegions/<id>/` | Up to two extracted region packages |
| `ImportedMap/` | Optional legacy photo/elevation overview |
| `RegionSetupComplete` | Records that first-run regional setup has completed |
| `Staging/` | Temporary map extraction and video export files |

The root and app-managed files use complete file protection and backup exclusion. `Staging/` is cleared only after the journal decodes and validates successfully. Interrupted atomic writes can leave protected `.write-*` sibling files; these are not automatic backups or an implemented recovery mechanism. Bundled public maps and fonts live in the read-only application bundle. The coverage-outline preference alone uses `UserDefaults`.

The schema remains version 1; newer fields are optional so older notebooks load. Journals are capped at **64 MiB**, with at most **10,000 entries of each type** and smaller per-field limits. An oversized, unknown-version or invalid journal is preserved and left unwritable. Do not “repair” such a journal by saving defaults over it. There is no automatic rollback copy or database migration framework.

## Maps and offline behavior

`RegionPacks` accepts a strict, bounded archive format. Import copies the selected ZIP into protected staging, validates and extracts that snapshot, then retains the same ZIP bytes. Loading extracts it into staging again and checks that its manifest still matches the selected catalog entry before publishing the working copy. [Map packages](MAP_PACKS.md) describes the checks and limits.

`MapRepository` owns the loaded region catalog, overview data and revision identifier. A revision change rebuilds the renderer. `OfflineMapStyle` creates the style in code using only local GeoJSON, fonts, imagery and PMTiles. Package source URLs are attribution text. `OfflineMapNetwork` supplies MapLibre's ephemeral URL-session configuration and rejects HTTP/HTTPS requests. This is a renderer safeguard, not a system firewall.

`MapViewport` handles the shared Web Mercator camera. `MapOverlayRenderer` updates saved objects, drawings and own position independently; camera changes reuse existing geometry. Layer visibility is a style change. `MGRS` formats coordinates within the supported Sweden envelope. `TerrainView` owns a persistent `TerrainScene` with separate terrain and overlay nodes; it uses the country elevation grid, not regional terrain data. See [Performance](PERFORMANCE.md) for measurements and remaining costs.

## Capture and speech

`CameraCapture` wraps Apple's camera picker. Photos are redrawn before JPEG encoding to drop source EXIF/GPS. `MediaVault` produces thumbnails and exports video without copied container metadata. System camera temporary files remain an OS-controlled boundary.

`LocalPhoto` displays view-owned pixels decoded by `LocalImageLoader`. Decoding is serial, off the main actor and limited to display size; it does not rewrite originals or maintain a shared media cache.

`VoiceRecorder` records locally and saves a 7S draft with time and optional position metadata. `LocalSpeech` uses `SpeechAnalyzer` with supported on-device transcribers. Only the explicit language-preparation action requests model installation. Transcription requires an installed model and does not fall back to a network recognizer. Playback and transcription stop when their view leaves or becomes inactive; voice capture attempts to finish on background/interruption.

## Making changes

- Keep file operations in services and schema rules in models. Views should not write journal JSON.
- Preserve the write-before-publish rule. Do not add fallible steps after replacing the journal and then report the whole save as failed.
- Add optional fields for compatible schema additions. A format change needs an explicit migration and old-journal tests.
- Keep imported content out of styles, executable code and resource URLs. Recheck the offline boundary whenever renderer or speech dependencies change.
- Regenerate the Xcode project after adding/moving Swift files. Keep dependency versions and build settings in `Scripts/generate_project.py`.
- Use `xcrun swift-format format --in-place <changed Swift files>` for edited code. The repository configuration uses four spaces and a 120-column line limit; avoid unrelated formatting churn.
- Test changed failure paths as well as the normal workflow. See [Testing](TESTING.md) and [Security](SECURITY.md).
