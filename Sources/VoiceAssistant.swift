import Cocoa
import Speech
import AVFoundation

/// On-demand Spanish voice recognition using Apple's native Speech framework.
/// Zero CPU / zero mic usage when idle; activates only when triggered by Option+G or menu.
final class VoiceAssistant {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var maxDurationTimer: Timer?

    private(set) var isListening: Bool = false
    private var latestTranscript: String = ""

    var onListeningStateChanged: ((Bool) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onCommandRecognized: ((String) -> Void)?
    var onStatusMessage: ((String) -> Void)?

    func toggleListening() {
        if isListening {
            finishAndDispatch()
        } else {
            requestPermissionsAndStart()
        }
    }

    private func requestPermissionsAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard authStatus == .authorized else {
                    self.onStatusMessage?("Activa Voz en Ajustes 🎤")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.startRecording()
                        } else {
                            self.onStatusMessage?("Activa Micrófono en Ajustes 🎤")
                        }
                    }
                }
            }
        }
    }

    private func startRecording() {
        stopEngineOnly()
        latestTranscript = ""

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            onStatusMessage?("Voz no disponible")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = [
            "Gabi",
            "Gabi túmbate",
            "Gabi levántate",
            "Gabi a la esquina",
            "Gabi pelota",
            "Gabi guapo",
            "Gabi ladra",
            "Gabi salta",
            "Gabi abre YouTube",
            "Gabi abre la uni",
            "Gabi pon nuestra canción"
        ]
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            onStatusMessage?("Error de micrófono")
            stopEngineOnly()
            return
        }

        isListening = true
        onListeningStateChanged?(true)

        // Safety max duration: 6.5s
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: 6.5, repeats: false) { [weak self] _ in
            self?.finishAndDispatch()
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty {
                    self.latestTranscript = text
                    self.onPartialTranscript?(text)
                    self.resetSilenceTimer()
                }
                if result.isFinal {
                    self.finishAndDispatch()
                }
            }
            if error != nil && self.isListening {
                self.finishAndDispatch()
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.35, repeats: false) { [weak self] _ in
            self?.finishAndDispatch()
        }
    }

    private func finishAndDispatch() {
        guard isListening else { return }
        let finalText = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopEngineOnly()
        isListening = false
        onListeningStateChanged?(false)

        if !finalText.isEmpty {
            onCommandRecognized?(finalText)
        }
    }

    private func stopEngineOnly() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
