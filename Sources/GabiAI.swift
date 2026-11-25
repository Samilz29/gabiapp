import Cocoa

/// Lightweight native URLSession client for Gemini API (0% CPU when idle, 0 external dependencies).
final class GabiAI {
    static let shared = GabiAI()
    private let keyDefaultsKey = "gabi.geminiApiKey"

    private init() {}

    var apiKey: String {
        get { (UserDefaults.standard.string(forKey: keyDefaultsKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keyDefaultsKey) }
    }

    var isConfigured: Bool {
        return !apiKey.isEmpty
    }

    func promptForApiKey(completion: @escaping (Bool) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Configurar IA de Gabi (Gemini)"
        alert.informativeText = "Pega tu API Key gratuita de Google AI Studio (aistudio.google.com). Se guarda solo en tu Mac."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")
        if isConfigured {
            alert.addButton(withTitle: "Borrar clave")
        }

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "AIza..."
        input.stringValue = apiKey
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            apiKey = input.stringValue
            completion(isConfigured)
        } else if response == .alertThirdButtonReturn {
            apiKey = ""
            completion(false)
        } else {
            completion(isConfigured)
        }
    }

    func ask(_ question: String, completion: @escaping (String?) -> Void) {
        let key = apiKey
        guard !key.isEmpty else {
            completion(nil)
            return
        }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(key)"
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [
                    [
                        "text": "Eres Gabi, un perrito pomerania virtual muy cariñoso, fiel y listo que vive en el escritorio de su dueño. Responde siempre en español, en máximo 1 o 2 frases muy breves (menos de 130 caracteres) y claras."
                    ]
                ]
            ],
            "contents": [
                [
                    "parts": [
                        ["text": question]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 90,
                "temperature": 0.6
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil)
            return
        }
        req.httpBody = httpBody

        URLSession.shared.dataTask(with: req) { data, response, error in
            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let clean = text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion(clean.isEmpty ? nil : clean)
            }
        }.resume()
    }
}
