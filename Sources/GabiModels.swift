import Cocoa
import ImageIO

enum GabiState: String {
    case idle
    case sitting
    case walking
    case running
    case jumping
    case barking
    case resting
    case happy
    case dragging
    case listening

    var statusDescription: String {
        switch self {
        case .idle: return "Gabi te está mirando"
        case .sitting: return "Gabi está sentado"
        case .walking: return "Gabi está paseando"
        case .running: return "Gabi está corriendo feliz"
        case .jumping: return "Gabi está saltando"
        case .barking: return "Gabi dice ¡Guau!"
        case .resting: return "Gabi está descansando"
        case .happy: return "Gabi está muy contento ♥"
        case .dragging: return "Llevando a Gabi"
        case .listening: return "🎤 Gabi te está escuchando..."
        }
    }

    var frames: [String] {
        switch self {
        case .idle:
            return ["idle_front", "idle_front", "idle_side", "idle_front"]
        case .sitting:
            return ["sit_front", "sit_front", "sit_side", "sit_front"]
        case .walking:
            return ["walk_1", "walk_2", "walk_3", "walk_2"]
        case .running:
            return ["run_1", "run_2", "run_3", "run_2"]
        case .jumping:
            return ["jump_1", "jump_2", "jump_3"]
        case .barking:
            return ["bark_1", "bark_2", "bark_3", "bark_2", "bark_1"]
        case .resting:
            return ["rest_lying", "rest_sleep", "rest_sleep", "rest_sleep", "rest_sleep"]
        case .happy:
            return ["happy_front", "happy_hop_1", "happy_hop_2", "happy_front"]
        case .dragging:
            return ["jump_2"]
        case .listening:
            return ["sit_front"]
        }
    }

    var frameDuration: TimeInterval {
        switch self {
        case .idle: return 1.1
        case .sitting: return 1.3
        case .walking: return 0.16
        case .running: return 0.10
        case .jumping: return 0.16
        case .barking: return 0.18
        case .resting: return 3.2
        case .happy: return 0.22
        case .dragging: return 0.25
        case .listening: return 0.5
        }
    }
}

enum GabiSize: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var label: String {
        switch self {
        case .small: return "Pequeño"
        case .medium: return "Normal"
        case .large: return "Grande"
        }
    }

    var spriteSize: CGFloat {
        switch self {
        case .small: return 112
        case .medium: return 148
        case .large: return 192
        }
    }

    // Extra horizontal room for full-scale lying sprites (360x256) and vertical headroom for hearts/voice
    var windowSize: NSSize {
        let s = spriteSize
        return NSSize(width: ceil(s * 1.48) + 32, height: s + 68)
    }
}

struct FloatingParticle {
    let text: String
    let color: NSColor
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var age: CGFloat
    let lifetime: CGFloat
    let fontSize: CGFloat

    var alpha: CGFloat {
        let t = age / lifetime
        if t < 0.15 { return t / 0.15 }
        return max(0, 1.0 - (t - 0.15) / 0.85)
    }
}

final class SpriteStore {
    static let shared = SpriteStore()
    private var cache: [String: CGImage] = [:]

    private init() {
        loadAll()
    }

    private func spritesDirectory() -> URL? {
        if let bundleRes = Bundle.main.resourceURL?.appendingPathComponent("sprites"),
           FileManager.default.fileExists(atPath: bundleRes.path) {
            return bundleRes
        }
        let devURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets/sprites")
        if FileManager.default.fileExists(atPath: devURL.path) {
            return devURL
        }
        return nil
    }

    private func loadAll() {
        guard let dir = spritesDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }

        for url in files where url.pathExtension.lowercased() == "png" {
            let name = url.deletingPathExtension().lastPathComponent
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                cache[name] = cgImage
            }
        }
    }

    func sprite(named name: String) -> CGImage? {
        return cache[name] ?? cache["idle_front"]
    }
}

final class GabiPreferences {
    static let shared = GabiPreferences()
    private let defaults = UserDefaults.standard

    var size: GabiSize {
        get {
            if let raw = defaults.string(forKey: "gabi.size"), let val = GabiSize(rawValue: raw) {
                return val
            }
            return .medium
        }
        set { defaults.set(newValue.rawValue, forKey: "gabi.size") }
    }

    var roamEnabled: Bool {
        get {
            if defaults.object(forKey: "gabi.roam") == nil { return true }
            return defaults.bool(forKey: "gabi.roam")
        }
        set { defaults.set(newValue, forKey: "gabi.roam") }
    }

    var followMouse: Bool {
        get { defaults.bool(forKey: "gabi.followMouse") }
        set { defaults.set(newValue, forKey: "gabi.followMouse") }
    }

    var stayResting: Bool {
        get { defaults.bool(forKey: "gabi.stayResting") }
        set { defaults.set(newValue, forKey: "gabi.stayResting") }
    }

    var soundEnabled: Bool {
        get {
            if defaults.object(forKey: "gabi.soundEnabled") == nil { return true }
            return defaults.bool(forKey: "gabi.soundEnabled")
        }
        set { defaults.set(newValue, forKey: "gabi.soundEnabled") }
    }

    var customBarkFilename: String? {
        get { defaults.string(forKey: "gabi.customBarkFilename") }
        set {
            if let v = newValue {
                defaults.set(v, forKey: "gabi.customBarkFilename")
            } else {
                defaults.removeObject(forKey: "gabi.customBarkFilename")
            }
        }
    }
}
