# Validation

## Current validation — 2026-09-25

Xcode 27.0 / iOS 27.0 SDK, iPhone 18 Pro simulator, Swift 6 strict concurrency.

- Unit/integration suite: **17 passed, 1 physical-device-only skipped**. Covers independent MGRS reference values, fit-to-country bounds, legacy journal compatibility, manual-position and voice persistence/deletion, preconfigured Gotland, two-region loading/relaunch/archiving, third-region rejection and malicious ZIP inputs.
- UI suite: **6 passed**, covering portrait and both landscape orientations, detailed map modes/drawing, annotation persistence, background locking, report lifecycle, manual position/voice capture/playback and the two-region coverage toggle. Full results are in `build/FieldFinal.xcresult`; the final button-contrast orientation check also passes in `build/LayerContrastVerified.xcresult`.
- Unsigned physical-device **Release build succeeds** with minimum OS 27.0. The binary excludes all simulator preview/reset arguments and includes all five offline packages.
- Each regional archive's manifest and extracted PMTiles SHA-256 matches `Scripts/regions.json`. The map preparation command and generated project are checked. `git diff --check` and property-list validation pass.
- UI tests use a separate simulator data directory and synthetic observations. They do not reset the ordinary app's notebook. Screenshots are full-screen XCTest captures to avoid incorrect app-window crops after rotation.

Simulator checks do **not** validate real camera/GNSS performance, Swedish/English transcription accuracy, locked-device encryption, thermal/battery behavior or operation in field conditions. Language models were not downloaded during the UI tests; the offline-unavailable path preserves the recording.

## Automated

Run the shared Heimdall scheme's tests on an iOS 27 simulator. The test suite covers:

- Forward/inverse Web Mercator, country fitting and independently generated MGRS reference values.
- Bundled vector, photo and elevation package availability and validation.
- Invalid, incomplete and out-of-coverage annotations.
- 7S save/edit/sent/delete persistence across store reloads; explicit missing-field text and limits.
- Corrupt journal preservation and refusal to overwrite.
- Independent tactical layers and iOS file-protection/backup attributes.
- Symlink import rejection and unsafe elevation dimensions.
- Photo persistence, thumbnail creation and deletion.
- UI map-mode switching, point creation, relaunch persistence and deletion.
- UI 7S creation, radio-text reading, marking sent and deletion.
- UI background lock and explicit unlock on return.
- Complete map-import/replacement/failure/restore lifecycle.

## Physical iPhone acceptance (required separately)

1. Install a signed Release build on iOS 27 with a passcode. Cold launch and authenticate. Repeat with Face ID unavailable and use the passcode. Check that removing the device passcode prevents a new unlock.
2. Enable airplane mode and disable Wi-Fi. Terminate/relaunch the app. Verify vector, photo and 3D maps without prior app network access. Repeat after reboot/unlock.
3. Add one point, line and area to each layer. Pan/zoom; verify geometric alignment in Photo and 3D. Toggle visibility, relaunch and verify persistence. Check imported regional coverage and handling of invalid packs.
4. Capture portrait/landscape photos, front/rear camera and audio/video. Wait for vault confirmation, relaunch and play them offline. Verify no Photos-library entries and inspect image/video metadata outside the operational device using dedicated test media.
5. Test capture cancellation, denied camera/microphone access, low storage, interruption, locking and backgrounding during export. Confirm explicit failure handling and inspect the app sandbox for temporary/orphaned files.
6. Enter Swedish 7S text, incomplete drafts and long fields. Cancel edits, save changes, reopen, mark sent, edit again (clears sent), delete, relaunch. Use VoiceOver and largest accessibility text sizes.
7. Background from map, report editor, reader, media detail and active camera. Verify obscured app-switcher snapshots and authentication on return. Start screen recording/mirroring with sheets presented; verify the separate privacy window covers them. Check screenshot behavior is accurately documented.
8. Verify data protection on a locked physical device and backup exclusion using a test backup. A simulator cannot establish the device's cryptographic protection.
9. Check GPS outdoors with radios disabled; test denied, approximate and stale locations. GPS availability/accuracy is an environmental constraint. Verify updates stop on lock and background.
10. Have a separate reviewer audit the signed Release app, provisioning, data paths, imported-map trust, temporary capture lifecycle and device configuration before field use.

Use synthetic observations for testing. The app deliberately does not ship sample tactical positions or fictional report content in normal use.

## Added device checks for regions and voice

1. Install both Swedish and English speech models using Device → Offline speech while connected. Enable airplane mode, record known phrases in each language, transcribe and compare against the recordings. Check an unsupported language/device and a missing/evicted model: keep the audio and manual editor available, with no cloud fallback.
2. Start with Gotland, load Stockholm, archive Gotland, then load Uppland. Pan across the Stockholm/Uppland overlap at street level. Relaunch offline and confirm both remain loaded. Attempt a third region and verify that nothing is silently removed.
3. Check all five regional extracts near their declared edges, the country overview outside them, and coverage outlines on/off in Vector, Photo and 3D. Package boundaries are rectangular data extents, not province borders.
4. Record with GPS off/no manual fix, a current GPS fix, and an old manual position. Confirm time, source, MGRS coordinate, position age and GPS accuracy. Location metadata must never silently become the observed object's Ställe.
5. Interrupt recording with a call, lock, background, route change and low storage; verify saved audio and duration. Kill the process mid-recording to assess partial/orphan data. Retry a failed save. Delete a report and confirm its audio file is removed.
6. Play, pause, scrub and leave a recording screen. Cancel transcription and background while transcribing. Confirm audio stops, the privacy shield covers the UI and the app requires authentication on return.
