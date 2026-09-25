# Security and data safety

Heimdall is a prototype, not an audited or accredited secure communications system. It reduces common disclosure risks by keeping data local and using iOS protection. **It cannot guarantee that a hostile force with a captured, unlocked or compromised phone cannot read the data.** There is also no guarantee against all data loss.

The useful boundary is specific: the app does not need a server to show maps, save notes, capture media or play recordings. Stored information relies on the phone's passcode, iOS Data Protection and the application sandbox. Authentication inside the app is an additional access gate, not a separate encryption key.

## What offline means here

| Activity | Network behavior |
| --- | --- |
| Maps, reports, annotations, media and playback | Local files; no app upload or sync implementation |
| Map rendering | App-owned local styles, glyphs and sources; MapLibre's ephemeral URL session rejects HTTP/HTTPS and has no cache, cookies or credentials |
| Voice transcription | Installed on-device speech models; missing/unsupported models produce an error, with no cloud recognizer fallback |
| Prepare language in Device settings | Explicitly asks Apple's system service to download a model; do this before going offline |
| Import a ZIP | Reads the selected file; a cloud document provider may itself download it |
| Preparing a development build | Map-preparation scripts and initial Swift package resolution use the internet |

No account, analytics SDK, cloud container or background mode is configured. These are properties of this implementation, not a phone-wide network ban. The MapLibre protocol does not intercept arbitrary sockets, other libraries, system dictation, Core Location or other apps. Dependencies and OS behavior still need verification on the deployed build.

Before offline testing, install the app and required speech models, put import packages under **On My iPhone**, then enable airplane mode and check Wi-Fi and Bluetooth separately. Verify the actual radio state required by your environment. The app cannot disable the phone's radios or promise radio silence. Use [physical-device testing](TESTING.md) to check behavior and observe network traffic independently.

Apple documents the on-device speech APIs in [SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/) and [DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber).

## Access and protection at rest

- `DeviceSecurity` requires device-owner authentication: biometrics or device passcode. A passcode must be configured. Backgrounding, manual lock and detected screen recording/mirroring lock the app. The Debug preview bypass is compiled only for simulators, never for physical phones or Release.
- `SecureFiles` creates app-managed storage with `NSFileProtectionComplete`. The default data-protection entitlement requests the same class. Apple ties this protection to the device passcode and device hardware, and makes protected file data unavailable after device locking; see [Data Protection classes](https://support.apple.com/guide/security/data-protection-classes-secb010e978a/web).
- The app marks its private data root, journal, attachments, map copies and staging files as excluded from backup. Replacement files receive these attributes before publication. Apple's [backup exclusion API](https://developer.apple.com/documentation/foundation/urlresourcekey/isexcludedfrombackupkey) describes this flag; verify its effect in an actual test backup.
- There is no app-specific encryption password, per-report key or end-to-end encryption scheme. Pressing **Lock now** hides the app and stops location; it does not lock iOS or purge already loaded data from memory.

An unlocked device, OS compromise, forensic exploit, coerced authentication or someone photographing the screen remains outside this protection. Protection attributes in a simulator are not proof of encryption on a physical phone.

## What information stays on the phone

The journal contains report text, transcripts, annotation coordinates, callsign, manual position and attachment metadata. Photo/video entries retain capture time and file size, but do not add a capture coordinate. Photos are redrawn without source EXIF/GPS; video export omits copied container metadata. The image or audio content itself can still reveal places, people, callsigns and other sensitive details. Inspect exported video metadata with synthetic footage on the target OS.

Voice reports retain recording time and, when available, a GPS/manual position snapshot with its timestamp and accuracy. Clearing the current manual marker does not remove those historical snapshots. GPS is opt-in, foreground-only, stops on lock/background and has no continuous track log. Core Location may use OS-provided location sources. A stale or invalid fix is not presented as a current GPS position.

The private vault does not save captures to Photos. There is no dedicated share/export/upload action. **Editable text can still be copied through the system editing menu, and transcripts and map source text are selectable.** Copied text leaves the app's protection boundary and may be available through system clipboard features. Disabling third-party keyboards and autocorrection does not disable system dictation, clipboard access or all OS text services. Configure the device accordingly; the app cannot promise those services never disclose input.

A separate privacy window covers app-switcher snapshots, inactive scenes and detected screen recording/mirroring, including presented sheets. It cannot prevent screenshots, frames captured before detection or a separate camera. Screenshots belong to the system Photos workflow and may sync according to device settings.

## Saving, failure and recovery

Journal changes validate and save before the UI reports success. The replacement file is fully written, protected and synchronized before an atomic rename. If that save fails, the previous journal and published state remain. Invalid or unsupported journals are preserved and cannot be silently overwritten. These checks reduce partial-write and validation failures; they are not a storage-hardware guarantee.

Attachment deletion commits its intent before removing bytes. If interrupted, the saved queue resumes after relaunch. A cleanup failure displays a warning and offers retry in Device settings. Until cleanup succeeds, deleted attachments may remain in protected storage. Ordinary deletion and replacement **do not guarantee forensic erasure on flash storage**. There is no panic-wipe or remote-wipe feature.

Capture and journal updates are not one atomic operation. Low storage, process termination, device locking or camera/audio interruption can leave incomplete or unindexed files. Voice recording attempts to finish on background/interruption and offers retry after a report-save failure while the capture view remains alive. Keep the app open until it confirms the saved entry, then reopen/play it. Unsaved editors and drawings are temporary.

Staging is cleaned after a successful journal load. Unknown media/voice files are not automatically deleted because they may be the only surviving capture. There is no in-app orphan recovery tool. System camera temporary files are outside the app's fully controlled capture pipeline; a production hardening effort should replace the picker with an owned AVFoundation pipeline and test interruption/metadata handling.

**Backup exclusion trades recovery for reduced replication.** Losing or damaging the phone, deleting the app, forgetting its passcode or losing access to the device can lose the only copy. There is no supported export/restore workflow, automatic backup, rollback journal or sync replica. Atomic writes do not change that. Do not delete/reinstall the app to troubleshoot a journal error; preserve the container for an authorized recovery review.

## Imported maps and dependencies

ZIP imports allow only the defined regular files. Compressed copying and extraction are bounded; traversal, symlinks, duplicate entries, oversized content, invalid bounds, CRC/hash mismatches and invalid PMTiles headers are rejected. The app validates a private snapshot and keeps those exact bytes. Imported content cannot supply a style or remote resource URL.

SHA-256 checks establish agreement with the included manifest, **not who produced it**. An attacker can replace a map and its manifest together. Packs are unsigned, internal tiles still reach third-party parsers, and a structurally valid map can be false or outdated. Only use sources trusted for the intended task. Pinned dependencies help reproducibility but do not prove the absence of vulnerabilities.

## Before sensitive use

Complete the physical-device checks in [Testing](TESTING.md), have the signed build and device configuration independently reviewed, and decide how data should be retained or recovered. This prototype has not established resistance to an adversary with forensic capabilities. It is also not validated for navigation, GNSS accuracy, TAK interoperability or military symbology compliance.

Keep operational data out of Git, test results and screenshots. The ignored `LocalData/` directory is for authorized local debugging copies; ignore rules are neither encryption nor secret detection and do not untrack existing files. Builds require no API keys or committed signing material. Git history also records author/committer identities independently of app data.
