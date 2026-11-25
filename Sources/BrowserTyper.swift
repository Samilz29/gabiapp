import Cocoa
import ApplicationServices

/// Lets Gabi open websites, launch Mac apps, and physically type into the browser search bar!
final class BrowserTyper {
    static let shared = BrowserTyper()

    private init() {}

    var hasAccessibilityPermission: Bool {
        return AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the user's default browser, creates a new tab (⌘T), and types the text + Return
    /// if Accessibility permission is granted. Falls back cleanly to opening the URL directly.
    func typeInBrowser(textToType: String, fallbackURL: URL, completion: @escaping () -> Void) {
        guard hasAccessibilityPermission else {
            // Ask permission once so next time Gabi can physically type, and still open right away!
            requestAccessibilityPermission()
            NSWorkspace.shared.open(fallbackURL)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                completion()
            }
            return
        }

        // Activate default HTTP browser
        if let browserURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://www.google.com")!) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: browserURL, configuration: config) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    // Open a fresh tab (⌘T) which automatically focuses the address/search bar
                    self.pressShortcut(keyCode: 17, flags: .maskCommand) // 'T' = 17
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                        self.typeStringAnimated(textToType) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                self.pressKey(keyCode: 36) // Return
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    completion()
                                }
                            }
                        }
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(fallbackURL)
            completion()
        }
    }

    /// Launches a macOS application by friendly Spanish or English name.
    @discardableResult
    func openApp(named rawName: String) -> Bool {
        let clean = rawName
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let aliases: [String: String] = [
            "musica": "Music",
            "música": "Music",
            "notas": "Notes",
            "ajustes": "System Settings",
            "configuracion": "System Settings",
            "configuración": "System Settings",
            "calculadora": "Calculator",
            "calendario": "Calendar",
            "mensajes": "Messages",
            "fotos": "Photos",
            "correo": "Mail",
            "vs code": "Visual Studio Code",
            "vscode": "Visual Studio Code",
            "visual studio": "Visual Studio Code",
            "chrome": "Google Chrome",
            "google chrome": "Google Chrome",
            "safari": "Safari",
            "firefox": "Firefox",
            "arc": "Arc",
            "brave": "Brave Browser",
            "spotify": "Spotify",
            "discord": "Discord",
            "whatsapp": "WhatsApp",
            "telegram": "Telegram",
            "terminal": "Terminal",
            "finder": "Finder",
            "slack": "Slack",
            "notion": "Notion"
        ]

        let targetName = aliases[clean] ?? clean
        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]

        let fm = FileManager.default
        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let appBase = String(item.dropLast(4))
                if appBase.lowercased() == targetName.lowercased() ||
                    appBase.lowercased().contains(targetName.lowercased()) {
                    let appURL = URL(fileURLWithPath: dir).appendingPathComponent(item)
                    let cfg = NSWorkspace.OpenConfiguration()
                    cfg.activates = true
                    NSWorkspace.shared.openApplication(at: appURL, configuration: cfg, completionHandler: nil)
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Low-level CGEvent Typing

    private func typeStringAnimated(_ text: String, completion: @escaping () -> Void) {
        let chars = Array(text)
        func nextChar(_ index: Int) {
            if index >= chars.count {
                completion()
                return
            }
            sendUnicodeChar(chars[index])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.042) {
                nextChar(index + 1)
            }
        }
        nextChar(0)
    }

    private func sendUnicodeChar(_ ch: Character) {
        let utf16 = Array(String(ch).utf16)
        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        else { return }

        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func pressKey(keyCode: CGKeyCode) {
        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func pressShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
