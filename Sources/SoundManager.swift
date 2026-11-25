import Cocoa
import AVFoundation
import UniformTypeIdentifiers

final class SoundManager {
    static let shared = SoundManager()
    private var audioPlayer: AVAudioPlayer?

    private init() {}

    var customAudioDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Gabi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var customBarkURL: URL? {
        guard let filename = GabiPreferences.shared.customBarkFilename else { return nil }
        let url = customAudioDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var bundledBarkURL: URL? {
        if let res = Bundle.main.resourceURL?.appendingPathComponent("sounds/gabi_bark.wav"),
           FileManager.default.fileExists(atPath: res.path) {
            return res
        }
        return nil
    }

    var activeBarkURL: URL? {
        return customBarkURL ?? bundledBarkURL
    }

    var hasCustomBark: Bool {
        return customBarkURL != nil
    }

    func playBark() {
        guard GabiPreferences.shared.soundEnabled else { return }
        guard let url = activeBarkURL else { return }

        audioPlayer?.stop()
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = 0.9
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        }
    }

    func chooseCustomBarkAudio(completion: @escaping (Bool) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Elegir audio de ladrido para Gabi"
        panel.message = "Selecciona un archivo de audio (.mp3, .m4a, .wav, .aiff, .caf)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]

        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let sourceURL = panel.url else {
                completion(false)
                return
            }

            let ext = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension.lowercased()
            let destName = "custom_bark.\(ext)"
            let destURL = self.customAudioDirectory.appendingPathComponent(destName)

            // Clean up any previous custom bark file
            if let oldName = GabiPreferences.shared.customBarkFilename {
                let oldURL = self.customAudioDirectory.appendingPathComponent(oldName)
                try? FileManager.default.removeItem(at: oldURL)
            }
            try? FileManager.default.removeItem(at: destURL)

            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                GabiPreferences.shared.customBarkFilename = destName
                GabiPreferences.shared.soundEnabled = true
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    func removeCustomBark() {
        if let oldName = GabiPreferences.shared.customBarkFilename {
            let oldURL = customAudioDirectory.appendingPathComponent(oldName)
            try? FileManager.default.removeItem(at: oldURL)
        }
        GabiPreferences.shared.customBarkFilename = nil
    }
}
