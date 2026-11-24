import AVFoundation
import Speech

/// Arabic speech recognition for the voice recitation test (Web Speech API is not available in WKWebView).
final class SpeechEngine {
    static let shared = SpeechEngine()

    /// (event, payload) -> "result" [text, isFinal] | "end" | "error" [code]
    var onEvent: ((String, [String: Any]) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var wanted = false

    var available: Bool { SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))?.isAvailable ?? false }

    func start(lang: String) {
        wanted = true
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { self.fail("not-allowed"); return }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else { self.fail("not-allowed"); return }
                        self.begin(lang: lang)
                    }
                }
            }
        }
    }

    func stop() {
        wanted = false
        teardown()
    }

    private func begin(lang: String) {
        guard wanted else { return }
        teardown()
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: lang.isEmpty ? "ar-SA" : lang)), rec.isAvailable else {
            fail("network"); return
        }
        recognizer = rec
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { fail("aborted"); return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in req.append(buf) }
        engine.prepare()
        do { try engine.start() } catch { fail("aborted"); return }

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let r = result {
                let text = r.bestTranscription.formattedString
                DispatchQueue.main.async { self.onEvent?("result", ["text": text, "isFinal": r.isFinal]) }
                if r.isFinal { DispatchQueue.main.async { self.teardown(); self.onEvent?("end", [:]) } }
            } else if error != nil {
                // silence / timeout: end so the page restarts listening while the test is on
                DispatchQueue.main.async { self.teardown(); if self.wanted { self.onEvent?("end", [:]) } }
            }
        }
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
    }

    private func fail(_ code: String) {
        wanted = false
        teardown()
        onEvent?("error", ["code": code])
    }
}
