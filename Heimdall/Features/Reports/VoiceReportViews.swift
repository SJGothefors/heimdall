import AVFoundation
import SwiftUI

struct VoiceCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let report: SevenSReport
    let store: LocalStore
    let location: LocationService
    var onSaved: (SevenSReport) -> Void
    @State private var recorder = VoiceRecorder()
    @State private var language = "sv-SE"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("Recording language", selection: $language) {
                        Text("Svenska").tag("sv-SE")
                        Text("English").tag("en-US")
                    }
                    .pickerStyle(.segmented).disabled(recorder.isRecording || recorder.isRequesting)
                    Image(systemName: "waveform").font(.system(size: 48)).foregroundStyle(
                        recorder.isRecording ? .red : Theme.accent)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds =
                            recorder.isRecording
                            ? max(0, Int(context.date.timeIntervalSince(recorder.startedAt ?? context.date))) : 0
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(
                            .system(.largeTitle, design: .monospaced))
                    }
                    if recorder.isRecording {
                        Button("Stop & save", systemImage: "stop.fill") { recorder.finish() }.buttonStyle(
                            PrimaryButtonStyle())
                    } else if !recorder.hasUnsavedRecording {
                        Button("Start recording", systemImage: "mic.fill") {
                            Task {
                                await recorder.start(
                                    report: report, store: store, location: location, language: language)
                            }
                        }.buttonStyle(PrimaryButtonStyle()).disabled(recorder.isRequesting)
                    }
                    Text(
                        "Up to 5 minutes. Saves as a 7S draft with recording time and your current GPS or manual position, when available."
                    )
                    .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    if location.currentPosition == nil {
                        Text("No position set").font(.caption).foregroundStyle(.orange)
                    }
                    if let message = recorder.message { Text(message).font(.footnote).foregroundStyle(.orange) }
                    if recorder.hasUnsavedRecording { Button("Retry saving") { recorder.savePending() } }
                }.padding(24)
            }.background(Theme.background)
                .navigationTitle("Voice report").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(recorder.isRecording ? "Save & close" : "Close") {
                            recorder.finish()
                            if !recorder.hasUnsavedRecording { dismiss() }
                        }
                    }
                }
                .interactiveDismissDisabled(
                    recorder.isRecording || recorder.isRequesting || recorder.hasUnsavedRecording
                )
                .onChange(of: recorder.savedReport) { _, saved in
                    if let saved {
                        onSaved(saved)
                        dismiss()
                    }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .background { recorder.finish() } }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
                    recorder.finish()
                }
                .onDisappear { recorder.finish() }
        }
    }
}

struct VoiceAttachmentView: View {
    @Binding var report: SevenSReport
    let store: LocalStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVAudioPlayer?
    @State private var playbackTask: Task<Void, Never>?
    @State private var preparingPlayback = false
    @State private var transcribing = false
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var error: String?
    @State private var language = "sv-SE"
    var body: some View {
        if let audio = report.recording {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        playbackTask = Task { await togglePlayback(audio) }
                    } label: {
                        Label("Play / pause", systemImage: "playpause.fill").frame(minHeight: 44)
                    }.disabled(preparingPlayback)
                    Spacer()
                    Text("\(Int(audio.duration)) s").font(.system(.caption, design: .monospaced))
                }
                if let player {
                    TimelineView(.periodic(from: .now, by: 0.3)) { _ in
                        Slider(
                            value: Binding(get: { player.currentTime }, set: { player.currentTime = $0 }),
                            in: 0...max(0.1, player.duration)
                        )
                        .accessibilityLabel("Recording playback position")
                    }
                }
                Text(audio.recordedAt, format: .dateTime.day().month().year().hour().minute().second()).font(.caption)
                if let position = audio.position {
                    Text("\(position.coordinate.formatted) · \(position.source.rawValue.uppercased())")
                        .font(.system(.caption, design: .monospaced))
                    Text(
                        "Position set \(position.timestamp.formatted(date: .abbreviated, time: .shortened))"
                            + (position.accuracy.map { " · ±\(Int($0)) m" } ?? "")
                    )
                    .font(.caption2).foregroundStyle(Theme.muted)
                } else {
                    Text("No position recorded").font(.caption).foregroundStyle(Theme.muted)
                }
                Picker("Transcription language", selection: $language) {
                    Text("Svenska").tag("sv-SE")
                    Text("English").tag("en-US")
                }.pickerStyle(.segmented).disabled(transcribing)
                Button(
                    transcribing ? "Cancel transcription" : "Transcribe offline",
                    systemImage: transcribing ? "stop" : "text.bubble"
                ) {
                    if transcribing {
                        transcriptionTask?.cancel()
                    } else {
                        player?.pause()
                        error = nil
                        transcribing = true
                        transcriptionTask = Task {
                            defer { transcribing = false }
                            do {
                                let text = try await LocalSpeech.transcribe(
                                    store.files.voiceDirectory.appendingPathComponent(audio.fileName),
                                    language: language)
                                try Task.checkCancellation()
                                report.transcript = text
                                report.recording?.language = language
                                report.updatedAt = .now
                            } catch is CancellationError {} catch { self.error = error.localizedDescription }
                        }
                    }
                }.frame(minHeight: 44)
                if transcribing { ProgressView("Transcribing on this iPhone…") }
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
            }.onAppear { language = audio.language }
                .onDisappear { stop() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { stop() } }
        }
    }
    private func togglePlayback(_ audio: VoiceRecording) async {
        if player?.isPlaying == true {
            player?.pause()
            return
        }
        preparingPlayback = true
        defer { preparingPlayback = false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            guard try await session.activate(options: []) else { throw AppError.invalidMedia }
            try Task.checkCancellation()
            guard scenePhase == .active else { return }
            if player == nil {
                player = try AVAudioPlayer(
                    contentsOf: store.files.voiceDirectory.appendingPathComponent(audio.fileName))
            }
            guard player?.play() == true else { throw AppError.invalidMedia }
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func stop() {
        playbackTask?.cancel()
        player?.stop()
        player = nil
        transcriptionTask?.cancel()
        AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) { _, _ in }
    }
}
