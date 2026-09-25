import AVFoundation
import Speech

nonisolated enum LocalSpeech {
    enum Failure: LocalizedError {
        case unsupported, modelMissing, empty
        var errorDescription: String? {
            switch self {
            case .unsupported:
                "This device does not support offline transcription for this language. Your recording is still available."
            case .modelMissing:
                "Prepare this language in Device → Offline speech while connected, then try again. Your recording stays on this iPhone."
            case .empty: "No speech was recognized. Listen to the recording and write your notes manually."
            }
        }
    }
    enum Engine: Sendable {
        case speech(SpeechTranscriber), dictation(DictationTranscriber)
        var module: any SpeechModule {
            switch self {
            case .speech(let value): value
            case .dictation(let value): value
            }
        }
        func collect() async throws -> String {
            var chunks: [String] = []
            switch self {
            case .speech(let module):
                for try await result in module.results where result.isFinal {
                    try Task.checkCancellation()
                    chunks.append(String(result.text.characters))
                }
            case .dictation(let module):
                for try await result in module.results where result.isFinal {
                    try Task.checkCancellation()
                    chunks.append(String(result.text.characters))
                }
            }
            return String(chunks.joined(separator: " ").prefix(30_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    static func engine(_ language: String) async throws -> Engine {
        guard ["sv-SE", "en-US"].contains(language) else { throw Failure.unsupported }
        let locale = Locale(identifier: language)
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .speech(SpeechTranscriber(locale: supported, preset: .transcription))
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .dictation(DictationTranscriber(locale: supported, preset: .longDictation))
        }
        throw Failure.unsupported
    }
    static func status(_ language: String) async -> String {
        guard let engine = try? await engine(language) else { return "Not supported on this device" }
        switch await AssetInventory.status(forModules: [engine.module]) {
        case .installed: return "Ready offline"
        case .supported: return "Download needed"
        case .downloading: return "Downloading…"
        default: return "Not supported on this device"
        }
    }
    /// This is the only path that asks the system to download speech models.
    /// It is called explicitly from Device settings, never during transcription.
    static func prepare(_ language: String) async throws {
        let engine = try await engine(language)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [engine.module]) {
            try await request.downloadAndInstall()
        }
    }
    static func transcribe(_ url: URL, language: String) async throws -> String {
        let engine = try await engine(language)
        guard await AssetInventory.status(forModules: [engine.module]) == .installed else { throw Failure.modelMissing }
        let analyzer = SpeechAnalyzer(modules: [engine.module])
        return try await withTaskCancellationHandler {
            let results = Task { try await engine.collect() }
            do {
                let audio = try AVAudioFile(forReading: url)
                try await analyzer.start(inputAudioFile: audio, finishAfterFile: true)
                let text = try await results.value
                guard !text.isEmpty else { throw Failure.empty }
                return text
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}
