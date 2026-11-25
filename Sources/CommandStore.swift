import Cocoa

struct CustomVoiceCommand: Codable {
    let frases: [String]
    let tipo: String       // "url", "app", "buscar", "accion"
    let valor: String
    let mensaje: String?
    let ladrar: Bool?
    let corazones: Bool?
    let teclear: Bool?
}

struct CustomCommandsFile: Codable {
    let comandos: [CustomVoiceCommand]
}

/// Loads and manages user-editable custom voice commands stored in
/// ~/Library/Application Support/Gabi/commands.json.
/// Reloads automatically on every voice command so edits take effect immediately!
final class CommandStore {
    static let shared = CommandStore()

    private init() {
        ensureDefaultFileExists()
    }

    var commandsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Gabi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("commands.json")
    }

    func ensureDefaultFileExists() {
        let url = commandsFileURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        let starter = """
        {
          "comandos": [
            {
              "frases": ["pon nuestra cancion", "nuestra cancion", "hay un amigo en mi"],
              "tipo": "url",
              "valor": "https://www.youtube.com/results?search_query=hay+un+amigo+en+mi+espanol",
              "mensaje": "🎵 Nuestra canción ♥",
              "ladrar": true,
              "corazones": true,
              "teclear": false
            },
            {
              "frases": ["abre la uni", "la uni", "universidad"],
              "tipo": "app",
              "valor": "Safari",
              "mensaje": "📚 ¡A la uni!",
              "ladrar": true,
              "corazones": false,
              "teclear": false
            }
          ]
        }
        """
        try? starter.data(using: .utf8)?.write(to: url)
    }

    func openInEditor() {
        ensureDefaultFileExists()
        NSWorkspace.shared.open(commandsFileURL)
    }

    func match(normalizedCommand: String) -> CustomVoiceCommand? {
        ensureDefaultFileExists()
        guard let data = try? Data(contentsOf: commandsFileURL),
              let parsed = try? JSONDecoder().decode(CustomCommandsFile.self, from: data)
        else { return nil }

        for item in parsed.comandos {
            for rawPhrase in item.frases {
                let phrase = rawPhrase
                    .lowercased()
                    .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !phrase.isEmpty && (normalizedCommand == phrase || normalizedCommand.contains(phrase)) {
                    return item
                }
            }
        }
        return nil
    }
}
