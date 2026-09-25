# Security design and boundaries

Heimdall is a development implementation, not an independently audited or accredited military system.

## Implemented

- All map styles, fonts and sources resolve to app-owned local files. MapLibre has networking capability, but its session is ephemeral, has no disk URL cache, and rejects HTTP/HTTPS using an installed URLProtocol. No remote style, telemetry SDK, accounts or cloud containers are used. No background modes are requested.
- SpeechAnalyzer/DictationTranscriber performs on-device transcription. An explicit Device settings action downloads Apple language models while connected; recording and transcription do not upload audio or fall back to a cloud recognizer. Speech hardware/language availability must be checked on the target phone.
- Authentication uses `LAContext` with device-owner authentication (biometric or device passcode). A passcode is required. Backgrounding locks the UI; re-entry requires authentication. A manual lock stops location updates.
- Files and directories use `NSFileProtectionComplete`; the app also declares complete protection as its default data-protection entitlement. JSON writes use atomic replacement and complete file protection. Media and map-import staging directories are protected.
- The entire private Application Support directory, imported maps, journal, media, voice recordings, thumbnails and staging files are explicitly excluded from backups.
- A privacy window above presented content obscures app-switcher snapshots and app UI while the scene is inactive or captured. Screen recording/mirroring locks the app. This does not prevent screenshots, already-captured frames or a separate camera photographing the screen.
- Photos are redrawn and JPEG-encoded without copying source EXIF/GPS. Video exports explicitly omit container metadata. Photo/video capture does not add a capture coordinate to the journal. **Voice reports do retain recording time and an optional GPS/manual position snapshot**, including the position timestamp and accuracy when available. Verify video metadata on the physical-device OS version before deployment; device-generated temporary assets are initially owned by the system camera workflow.
- Photos and videos stay in the app sandbox. There is no automatic save to Photos, sharing action, clipboard export or transmission. Reports are displayed for the user to read over a separate radio.
- Third-party keyboard extensions are disabled by the application delegate. Report and transcript fields also disable autocorrection. The system keyboard, dictation and OS services remain controlled by iOS and device settings.
- GPS is off by default, requested only while in use, stops on lock/background and is not retained as tracks. Manual own-position is persisted until cleared. Voice recordings retain a position snapshot; clearing the current marker does not remove historical report metadata. Old or invalid fixes are not displayed as current positions. Core Location is an OS service and may use available system location sources; Heimdall does not control the phone's radios.
- Region ZIPs are restricted by filenames, entry types, decompressed size, valid bounds, CRC/SHA-256 and PMTiles header checks. Extraction streams bounded chunks into protected staging, rejecting traversal and symlinks. No executable package content is accepted. Existing data is not overwritten on validation failure.
- Journal updates are written before publishing new UI state. Decode failure blocks writing and preserves the original file.
- The operator callsign is stored in that protected, backup-excluded journal, not in UserDefaults or source code. It is used only as the local position marker's label and is not transmitted.

## Limits that matter

- iOS protects files against locked-device access. This is not end-to-end encryption, per-document key separation, or protection against a compromised/unlocked phone, malicious keyboard, kernel exploit, coerced authentication or forensic access to an already unlocked device.
- File deletion and atomic JSON replacement are ordinary filesystem operations. They do not guarantee forensic secure erasure on flash storage. There is no panic wipe or remote wipe feature.
- Disabling app network code does not disable iOS radios, assisted location services, screenshot/keyboard services or a cloud document provider selected by the user. Provision maps under **On My iPhone** for offline import and configure the actual phone for the intended environment.
- Capture may be interrupted by locking, low storage, phone calls or process termination. Voice capture stops and attempts to save on background/interruption; a process kill or storage failure can leave an orphan recording or incomplete audio. Keep the app open until it confirms the saved item in the vault. Temporary capture/export data can exist before completion; protected staging files are removed on the next successful journal load. Crash leftovers outside that staging directory may require app-container cleanup.
- The Apple camera picker does not publish a reliable guarantee about all its internally managed temporary file lifetimes. A hardened production build should use a fully owned AVFoundation capture pipeline, verify metadata and temporary files under interruption, and receive a separate security review.
- The journal is a bounded in-memory JSON store suitable for a small notebook. It has no concurrent writer, sync or recovery protocol. Retained media may fill the phone; file failures are reported, but automatic retention and a storage budget are not implemented.
- The app hides its sensitive UI when locked but does not promise that previously loaded objects have been zeroed out of RAM.
- `--ui-testing` bypasses authentication only in Debug **simulator** builds. The preprocessor excludes this path on physical devices and in Release. Test fixtures must never be operational data.
- Map packs are not signed. Regional OSM vectors are dated 2026-09-24; the nationwide photo/elevation remain historical overview data. The app cannot establish truth, currency or trustworthiness of map content or observations.

## Before operational use

Use the physical-device checks in `TESTING.md`, independent application/device security review, up-to-date licensed cartography, a deployment/signing policy, and an explicit data handling and retention policy. This build does not claim TAK interoperability, validated navigation, assured GNSS accuracy, or military symbology compliance.

## Repository hygiene

The source does not require API keys, signing private keys, or device passcodes. Runtime journals and media live in the iPhone/simulator's private app container, outside this repository. The bundled maps use public source data.

Keep operational reports, coordinates, media, and restricted map packs out of Git, including test fixtures and screenshots. If app data must be copied into the workspace for local debugging, use the ignored root `LocalData/` directory. `.gitignore` also excludes environment files, signing keys, app-container exports, test results, archives, and journals. Ignore rules do not protect already tracked files or detect secrets pasted into source code.

Git commits also contain author and committer identities. Use a [GitHub noreply email](https://docs.github.com/en/account-and-profile/how-tos/email-preferences/setting-your-commit-email-address) if you do not want a personal or work email published. Changing the email for future commits does not change existing history.
