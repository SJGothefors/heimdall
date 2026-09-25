import AVFoundation
import Observation
import UIKit

@MainActor @Observable final class VoiceRecorder: NSObject, @preconcurrency AVAudioRecorderDelegate {
    private(set) var isRecording = false
    private(set) var isRequesting = false
    private(set) var startedAt: Date?
    private(set) var savedReport: SevenSReport?
    private(set) var message: String?
    private var recorder: AVAudioRecorder?
    private var pending: SevenSReport?
    private var store: LocalStore?
    private var duration: TimeInterval = 0
    private var generation = 0
    var hasUnsavedRecording: Bool { pending != nil && !isRecording }

    func start(report: SevenSReport, store: LocalStore, location: LocationService, language: String) async {
        guard !isRecording, !isRequesting, pending == nil, savedReport == nil else { return }
        isRequesting = true
        message = nil
        let requestGeneration = generation
        defer { isRequesting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            message = "Allow microphone access in iPhone Settings to record a voice report."
            return
        }
        guard requestGeneration == generation, UIApplication.shared.applicationState == .active else { return }
        var draft = report
        let recordingID = UUID()
        let url = store.files.voiceDirectory.appendingPathComponent(recordingID.uuidString + ".m4a")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            guard try await session.activate(options: []) else { throw AppError.invalidMedia }
            guard requestGeneration == generation, UIApplication.shared.applicationState == .active else {
                session.deactivate(options: .notifyOthersOnDeactivation) { _, _ in }
                return
            }
            let start = Date()
            let recording = VoiceRecording(
                id: recordingID, recordedAt: start, duration: 0.1,
                position: location.currentPosition, language: language)
            guard
                FileManager.default.createFile(
                    atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
            else { throw AppError.invalidMedia }
            let audioRecorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 64_000,
                ])
            recorder = audioRecorder
            audioRecorder.delegate = self
            guard audioRecorder.prepareToRecord(), audioRecorder.record(forDuration: 300) else {
                throw AppError.invalidMedia
            }
            try SecureFiles.protect(url)
            if draft.stund.isEmpty {
                draft.stund =
                    start.formatted(date: .abbreviated, time: .standard) + " " + (TimeZone.current.abbreviation() ?? "")
            }
            // Capture location is metadata, not automatically the observed object's Ställe.
            draft.recording = recording
            draft.sentAt = nil
            self.store = store
            pending = draft
            startedAt = start
            isRecording = true
        } catch {
            recorder?.stop()
            recorder = nil
            try? FileManager.default.removeItem(at: url)
            AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) { _, _ in }
            message = error.localizedDescription
        }
    }
    func finish() {
        generation += 1
        guard let recorder, var report = pending, store != nil else { return }
        if recorder.isRecording {
            duration = recorder.currentTime
        } else if duration == 0 {
            duration = min(300, Date().timeIntervalSince(startedAt ?? .now))
        }
        self.recorder = nil
        recorder.stop()
        isRecording = false
        report.recording?.duration = max(0.1, min(300, duration))
        report.updatedAt = .now
        pending = report
        savePending()
        AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) { _, _ in }
    }
    func savePending() {
        guard let report = pending, let store else { return }
        do {
            if let audio = report.recording {
                try SecureFiles.protect(store.files.voiceDirectory.appendingPathComponent(audio.fileName))
            }
            try store.saveReport(report)
            savedReport = report
            pending = nil
        } catch {
            message = "Recording kept on this phone, but saving its report failed: \(error.localizedDescription)"
        }
    }
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag { message = "Recording was interrupted. The available audio has been kept." }
        finish()
    }
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        message = error?.localizedDescription ?? "Recording stopped unexpectedly."
        finish()
    }
}
