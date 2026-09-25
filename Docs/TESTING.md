# Testing

Use synthetic reports, positions and media. Keep result bundles, app-container copies and screenshots out of Git. Unit tests use temporary roots; the test host and UI tests use the separate `HeimdallUITests` app-data directory. UI tests reset only that directory. Normal app launches do not seed observations or clear the notebook.

## Run locally

With Xcode 27, the five prepared region ZIPs and an iOS 27 simulator installed:

```sh
xcodebuild -project Heimdall.xcodeproj -scheme Heimdall \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO \
  -collect-test-diagnostics never -parallel-testing-enabled NO \
  -resultBundlePath build/TestRun.xcresult test
```

Use a new result-bundle name each time. Add `-only-testing:HeimdallTests` for unit/integration tests or `-only-testing:HeimdallUITests` for UI tests. Once packages are resolved, `-disableAutomaticPackageResolution` prevents automatic version resolution; required package artifacts must already be cached.

For an unsigned physical-device Release build:

```sh
xcodebuild -project Heimdall.xcodeproj -scheme Heimdall \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/DeviceRelease CODE_SIGNING_ALLOWED=NO build
```

Building is not the same as installing or testing on a physical phone.

## Latest validation — 2026-09-25

Xcode 27.0, Swift 6 strict concurrency, iPhone 18 Pro simulator on iOS 27.0.

- Unit/integration suite: **38 passed, 1 physical-device-only skipped**, including storage failure and rendering checks, in `build/PerformanceUnit.xcresult`.
- UI suite: **6 workflows passed in one run**, in `build/PerformanceUI.xcresult`: background locking, voice/position, point persistence, rotation/map modes, report handling and region loading/coverage.
- Final rendering suite and point/rotation workflows also pass in `build/PerformanceFinal.xcresult` after the drawing-visibility adjustment. Exported synthetic screenshots were reviewed for maps, position labels and terrain.
- Unsigned physical-device **Release build succeeds**. Its binary excludes the simulator authentication/reset arguments, targets iOS 27 and contains all five region ZIPs.
- Project regeneration is deterministic; Python syntax, local documentation links, property lists and `git diff --check` pass. The new/reworked storage, policy and rendering files pass `swift-format` lint.

Xcode still reports an AVAudioSession main-thread warning during voice capture; the terrain UI run also reported a thread-priority warning. The recorder already uses asynchronous session activation/deactivation. These diagnostics still need device profiling. Passing functional tests do not establish responsiveness under load; see [Performance](PERFORMANCE.md) for the focused measurements and profiling workload.

Rendering tests check independent saved-object/draft/position updates, unchanged-frame reuse, native geometry and labels, map style sources, terrain mesh/material/camera preservation, and bounded photo decoding with orientation, cancellation and unchanged originals. The benchmark uses 2,000 synthetic points and prints both the former and current preparation times; it does not assert a machine-specific timing threshold.

The new tests exercise real filesystem failure during journal replacement, attachment preservation after failed saves, interrupted deletion recovery, unreadable/oversized journals, visible cleanup failure and retry, old journals, invalid media/shared recording rejection, backup exclusion after replacement, invalid bounds, local map-style resources, HTTP/HTTPS rejection through the configured URL session, and imported ZIP snapshot consistency.

The existing suites cover MGRS reference coordinates, projection and country fitting, annotations and layers, report persistence/edit/sent/delete, corrupt journals, media thumbnails, two-region loading/archiving/relaunch, malicious ZIP fixtures, navigation, rotation, callsign editing, voice capture/playback and background locking.

A passing URL-session test proves the configured interception path rejects a request. It is **not** a packet capture of every framework or OS service. Simulator testing does not validate locked-device cryptography, real camera/GNSS behavior, battery/thermal limits, speech accuracy or forensic resistance. Speech models are not prepared automatically during tests; the missing-model path must preserve audio.

## Physical-device acceptance

Run these checks on a signed Release build, with synthetic data, before considering sensitive use. Record the app build, iPhone model, OS version, steps and results. Repeat relevant checks after changing OS versions, capture code, storage or dependencies.

| Area | Check |
| --- | --- |
| Authentication | Cold launch with passcode; test biometrics and passcode fallback, manual lock, background/re-entry, and removal of the device passcode. Confirm simulator bypass arguments have no effect. |
| Offline operation | Install/prepare everything, enable airplane mode, disable Wi-Fi and verify Bluetooth state. Reboot, unlock and relaunch. Load both regions, write/read reports, capture/play media and use supported transcription without connectivity. |
| Network observation | Observe device traffic independently while exercising maps, reports, capture and transcription with synthetic data. Distinguish app traffic from OS traffic. Test language preparation separately as the deliberate online action. |
| Maps | Load two regions, attempt a third, archive one and relaunch. Check overlap, edges and coverage outlines in all modes. Import malformed ZIPs and confirm existing maps and reports survive. |
| Annotations/reports | Save/edit/delete points, lines, areas and incomplete 7S reports; relaunch after each. Verify marked-sent behavior, long fields, rotation, VoiceOver and large accessibility text. Check what happens to unsaved edits on lock/background. |
| Camera/vault | Test portrait/landscape, front/rear photo, video with audio, cancellation and denied permissions. Wait for confirmation, relaunch and play. Confirm no Photos entry; inspect photo/video metadata using dedicated test captures. |
| Voice/speech | Prepare Swedish and English explicitly, then transcribe known phrases offline. Check absent/evicted models and unsupported devices/languages. Confirm recordings and manual editing remain available and location metadata never silently becomes Ställe. |
| Interruptions/storage | Background, lock, interrupt with a call, change audio route and run low on storage during capture/export/save/delete. Confirm errors, playback stopping and deletion retries. Kill mid-recording; inspect partial/orphan files and staging in a test container. |
| Position | Test GPS off, manual position, current GPS, denied/approximate/stale fixes and outdoor operation with radios disabled. Check timestamps/accuracy, no background updates, and historical snapshots remaining after the current marker is cleared. |
| Screen privacy | Background with each sheet and camera open. Inspect app-switcher snapshots. Start recording/mirroring before and during use; verify the shield covers presented content. Confirm the documented screenshot and clipboard limits. |
| File protection/backups | Verify protected files become inaccessible on a locked physical phone. Inspect a test backup for exclusion of the journal, attachments, maps and staging; check attributes after replacement and interruption. |

Deletion is ordinary filesystem removal, not secure erasure. Do not interpret an empty vault or successful delete test as proof that flash data is unrecoverable. Testing also cannot establish the trustworthiness or accuracy of imported map content.

An independent review of the signed app, dependencies, device configuration and data-handling policy remains necessary for adversarial use. See [Security](SECURITY.md) for the boundaries these tests are intended to check.
