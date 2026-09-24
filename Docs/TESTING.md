# Validation

## Recorded run — 2026-09-24

- Xcode 27.0 (27A266a), iOS 27.0 SDK, iPhone 18 Pro simulator.
- Debug app and test targets built successfully with Swift 6 strict concurrency.
- Main suite: **13 passed, 1 explicitly skipped, 0 failures**. The skipped check reads device file-protection attributes, which the simulator does not expose.
- Additional map-import lifecycle test: **1 passed**, including importing, replacing, rejecting a corrupt replacement without losing the current pack, and restoring the bundled map.
- Responsive-layout follow-up: all **4 UI tests passed**, including portrait, landscape left/right, map modes, drawing controls, report editor and media screen. Full-screen captures are used because app-window screenshot crops can be incorrect after rotation with a separate privacy window.
- Unsigned physical-device **Release build succeeded**, minimum OS verified as iOS 27.0. The Release executable does not contain the simulator authentication-bypass argument.
- Screenshots are in `Screenshots/`, including portrait, landscape map modes, drawing, report editing and media.
- Bundled map and photo hashes match `DATA_MANIFEST.json`; property lists validate and `git diff --check` passes.
- Result bundles (ignored build artifacts): `build/Tests-Final.xcresult`, `build/MapImport.xcresult`, `build/Orientation.xcresult` and `build/Orientation-Verified.xcresult`.

Across the suite there are **15 distinct passing tests** and **1 physical-device-only skipped test**. Repeated orientation capture runs do not add to that distinct count. The final compact report/media layout passed the orientation test, its full-screen captures were visually inspected, and the physical-device Release build passed again.

Camera capture, actual GNSS reception, locked-device encryption behavior, signing/distribution and real field operation were **not** tested on a physical iPhone. The acceptance checks below remain required before operational use.

## Automated

Run the shared Heimdall scheme's tests on an iOS 27 simulator. The test suite covers:

- Forward/inverse Web Mercator and screen-coordinate projection.
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
