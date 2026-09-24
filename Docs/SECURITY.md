# Security design and boundaries

Heimdall is a development implementation, not an independently audited or accredited military system.

## Implemented

- No runtime HTTP client, remote map style, web view, telemetry SDK, accounts or cloud containers. All map bytes are bundled or explicitly imported. No networking entitlements or background modes are requested.
- Authentication uses `LAContext` with device-owner authentication (biometric or device passcode). A passcode is required. Backgrounding locks the UI; re-entry requires authentication. A manual lock stops location updates.
- Files and directories use `NSFileProtectionComplete`; the app also declares complete protection as its default data-protection entitlement. JSON writes use atomic replacement and complete file protection. Media and map-import staging directories are protected.
- The entire private Application Support directory, imported maps, journal, media, thumbnails and staging files are explicitly excluded from backups.
- A privacy window above presented content obscures app-switcher snapshots and app UI while the scene is inactive or captured. Screen recording/mirroring locks the app. This does not prevent screenshots, already-captured frames or a separate camera photographing the screen.
- Photos are redrawn and JPEG-encoded without copying source EXIF/GPS. Video exports explicitly omit container metadata. No capture coordinate is written into the journal. Verify video metadata on the physical-device OS version before deployment; device-generated temporary assets are initially owned by the system camera workflow.
- Photos and videos stay in the app sandbox. There is no automatic save to Photos, sharing action, clipboard export or transmission. Reports are displayed for the user to read over a separate radio.
- Third-party keyboard extensions are disabled by the application delegate. Report fields also disable autocorrection. The system keyboard, dictation and OS services remain controlled by iOS and device settings.
- Locations are requested only while in use, stop on lock/background and are not retained as tracks. Old or invalid fixes are not displayed as current positions. Core Location is an OS service and may use available system location sources; Heimdall does not control the phone's radios.
- Imported maps are restricted by filenames, byte sizes, image dimensions, valid bounds, counts and finite coordinates. No executable package content is accepted. Existing data is not overwritten on validation failure.
- Journal updates are written before publishing new UI state. Decode failure blocks writing and preserves the original file.

## Limits that matter

- iOS protects files against locked-device access. This is not end-to-end encryption, per-document key separation, or protection against a compromised/unlocked phone, malicious keyboard, kernel exploit, coerced authentication or forensic access to an already unlocked device.
- File deletion and atomic JSON replacement are ordinary filesystem operations. They do not guarantee forensic secure erasure on flash storage. There is no panic wipe or remote wipe feature.
- Disabling app network code does not disable iOS radios, assisted location services, screenshot/keyboard services or a cloud document provider selected by the user. Provision maps under **On My iPhone** for offline import and configure the actual phone for the intended environment.
- Capture may be interrupted by locking, low storage, phone calls or process termination. Keep the app open until it confirms the saved item in the vault. Temporary capture/export data can exist before completion; protected staging files are removed on the next successful journal load. Crash leftovers outside that staging directory may require app-container cleanup.
- The Apple camera picker does not publish a reliable guarantee about all its internally managed temporary file lifetimes. A hardened production build should use a fully owned AVFoundation capture pipeline, verify metadata and temporary files under interruption, and receive a separate security review.
- The journal is a bounded in-memory JSON store suitable for a small notebook. It has no concurrent writer, sync or recovery protocol. Retained media may fill the phone; file failures are reported, but automatic retention and a storage budget are not implemented.
- The app hides its sensitive UI when locked but does not promise that previously loaded objects have been zeroed out of RAM.
- `--ui-testing` bypasses authentication only in Debug **simulator** builds. The preprocessor excludes this path on physical devices and in Release. Test fixtures must never be operational data.
- Map packs are not signed and the included map is historical, low-detail overview data. The app cannot establish truth, currency or trustworthiness of map content or observations.

## Before operational use

Use the physical-device checks in `TESTING.md`, independent application/device security review, up-to-date licensed cartography, a deployment/signing policy, and an explicit data handling and retention policy. This build does not claim TAK interoperability, validated navigation, assured GNSS accuracy, or military symbology compliance.
