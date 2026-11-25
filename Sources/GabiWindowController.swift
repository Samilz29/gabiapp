import Cocoa

final class GabiPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class GabiWindowController: NSObject, GabiViewDelegate {
    let window: GabiPanel
    let gabiView: GabiView

    private(set) var state: GabiState = .idle {
        didSet {
            if oldValue != state {
                onStateChange?(state)
            }
        }
    }

    var onStateChange: ((GabiState) -> Void)?
    var onPreferencesChange: (() -> Void)?
    var contextMenuProvider: (() -> NSMenu)?

    private let ballController = BallWindowController()
    private let voiceAssistant = VoiceAssistant()
    private var hotkeyManager: HotkeyManager?
    private var isPerformingVoiceTask: Bool = false
    private var timer: Timer?
    private var currentInterval: TimeInterval = 1.0 / 20.0
    private var lastTickTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    private var stateElapsed: TimeInterval = 0
    private var stateDuration: TimeInterval = 3.0
    private var frameElapsed: TimeInterval = 0
    private var frameIndex: Int = 0
    private var zzzCooldown: TimeInterval = 0

    private var walkDirection: CGFloat = 1.0 // 1 = right, -1 = left

    override init() {
        let size = GabiPreferences.shared.size
        let winSize = size.windowSize
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        // Start Gabi comfortably near the bottom-right area of the desktop
        let startOrigin = NSPoint(
            x: screenFrame.maxX - winSize.width - 90,
            y: screenFrame.minY + 12
        )

        let panel = GabiPanel(
            contentRect: NSRect(origin: startOrigin, size: winSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.alphaValue = 0.0

        let view = GabiView(frame: NSRect(origin: .zero, size: winSize))
        view.spriteDrawSize = size.spriteSize
        panel.contentView = view

        self.window = panel
        self.gabiView = view

        super.init()
        view.delegate = self
        setupVoiceAndHotkey()
        updateSpriteFrame()
    }

    private func setupVoiceAndHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.toggleVoiceListening()
        }

        voiceAssistant.onListeningStateChanged = { [weak self] listening in
            guard let self = self else { return }
            if listening {
                self.gabiView.statusBubbleText = "🎤 Escuchando..."
                self.transition(to: .listening, duration: 10.0)
            } else {
                self.gabiView.statusBubbleText = nil
                if self.state == .listening {
                    self.transition(to: GabiPreferences.shared.stayResting ? .resting : .sitting, duration: 3.0)
                }
            }
        }

        voiceAssistant.onPartialTranscript = { [weak self] text in
            self?.gabiView.statusBubbleText = "🎤 \(text)"
        }

        voiceAssistant.onStatusMessage = { [weak self] msg in
            self?.showTemporaryBubble(msg, seconds: 2.5)
        }

        voiceAssistant.onCommandRecognized = { [weak self] transcript in
            self?.handleVoiceCommand(transcript)
        }
    }

    func toggleVoiceListening() {
        voiceAssistant.toggleListening()
    }

    private func showTemporaryBubble(_ text: String, seconds: TimeInterval = 2.0) {
        gabiView.statusBubbleText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if self?.gabiView.statusBubbleText == text {
                self?.gabiView.statusBubbleText = nil
            }
        }
    }

    func showAndStart() {
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.65
            window.animator().alphaValue = 1.0
        }

        // Greet the user warmly on startup (or stay resting if user left that mode on)
        if GabiPreferences.shared.stayResting {
            transition(to: .resting, duration: 999_999)
        } else {
            triggerBark(showGreeting: true)
        }
        lastTickTime = ProcessInfo.processInfo.systemUptime
        rescheduleTimer(interval: desiredTickInterval())
    }

    private func desiredTickInterval() -> TimeInterval {
        if ballController.isActive { return 1.0 / 30.0 }
        if GabiPreferences.shared.followMouse { return 1.0 / 20.0 }
        if !gabiView.particles.isEmpty { return 1.0 / 20.0 }
        switch state {
        case .walking, .running, .jumping:
            return 1.0 / 20.0
        case .barking, .happy:
            return 1.0 / 10.0
        case .idle, .sitting, .resting, .dragging, .listening:
            return 0.5 // 2 Hz when calm -> ~0.1% CPU!
        }
    }

    private func rescheduleTimer(interval: TimeInterval) {
        if timer != nil && abs(currentInterval - interval) < 0.005 { return }
        timer?.invalidate()
        currentInterval = interval
        let newTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        newTimer.tolerance = interval * 0.2
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func applySize(_ size: GabiSize) {
        GabiPreferences.shared.size = size
        let oldFrame = window.frame
        let newSize = size.windowSize
        let newOrigin = NSPoint(
            x: oldFrame.midX - newSize.width / 2,
            y: oldFrame.minY
        )
        window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true)
        gabiView.frame = NSRect(origin: .zero, size: newSize)
        gabiView.spriteDrawSize = size.spriteSize
        clampToScreen()
    }

    func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let origin = NSPoint(
            x: vis.midX - window.frame.width / 2,
            y: vis.minY + 24
        )
        window.setFrameOrigin(origin)
        triggerHappy()
    }

    /// Runs Gabi smoothly to the bottom-right corner and tucks him in peacefully so he's out of the way.
    func goToCorner() {
        ballController.hide()
        GabiPreferences.shared.followMouse = false
        let vis = currentScreenFrame()
        let cornerOrigin = NSPoint(
            x: vis.maxX - window.frame.width - 4,
            y: vis.minY + 4
        )
        gabiView.facingRight = cornerOrigin.x >= window.frame.origin.x
        transition(to: .running, duration: 2.0)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.65
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrameOrigin(cornerOrigin)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.gabiView.facingRight = false // Look gently inward from the right corner
            self.setStayResting(true)
            self.showTemporaryBubble("💤 En mi rinconcito", seconds: 2.0)
        })
    }

    // MARK: - User-triggered Actions

    func triggerPet() {
        if GabiPreferences.shared.stayResting {
            // Stay peacefully lying down while showing hearts
            spawnHearts(count: 4)
            return
        }
        transition(to: .happy, duration: 2.2)
        spawnHearts(count: 4)
    }

    func triggerJump() {
        if GabiPreferences.shared.stayResting {
            setStayResting(false)
        }
        transition(to: .jumping, duration: 0.72)
        spawnParticle(text: "✨", color: NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.35, alpha: 1.0), fontSize: 16)
    }

    func triggerBark(showGreeting: Bool = false) {
        SoundManager.shared.playBark()
        let text = showGreeting ? "¡Hola! 🐾" : "¡Guau!"
        spawnParticle(
            text: text,
            color: NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.86, alpha: 1.0),
            fontSize: 14
        )
        if !GabiPreferences.shared.stayResting {
            transition(to: .barking, duration: 1.15)
        }
    }

    func triggerRest() {
        transition(to: .resting, duration: 14.0)
        zzzCooldown = 1.2
    }

    func setStayResting(_ stay: Bool) {
        GabiPreferences.shared.stayResting = stay
        if stay {
            ballController.hide()
            GabiPreferences.shared.followMouse = false
            transition(to: .resting, duration: 999_999)
            zzzCooldown = 2.0
        } else {
            transition(to: .sitting, duration: 2.5)
        }
        onPreferencesChange?()
    }

    func throwBall() {
        if GabiPreferences.shared.stayResting {
            GabiPreferences.shared.stayResting = false
            onPreferencesChange?()
        }
        let screen = currentScreenFrame()
        let gabiCenter = NSPoint(x: window.frame.midX, y: window.frame.minY + gabiView.spriteDrawSize * 0.45)
        ballController.throwBall(from: gabiCenter, in: screen)
        gabiView.facingRight = ballController.position.x >= gabiCenter.x
        walkDirection = gabiView.facingRight ? 1.0 : -1.0
        transition(to: .running, duration: 12.0)
        rescheduleTimer(interval: desiredTickInterval())
    }

    func triggerHappy() {
        if GabiPreferences.shared.stayResting {
            spawnHearts(count: 3)
            return
        }
        transition(to: .happy, duration: 1.8)
        spawnHearts(count: 3)
    }

    // MARK: - State Machine & Loop

    private func transition(to newState: GabiState, duration: TimeInterval) {
        state = newState
        stateElapsed = 0
        stateDuration = duration
        frameElapsed = 0
        frameIndex = 0
        gabiView.isDragging = (newState == .dragging)
        if newState != .jumping {
            gabiView.jumpOffsetY = 0
        }
        updateSpriteFrame()
        rescheduleTimer(interval: desiredTickInterval())
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.6, max(0.01, now - lastTickTime))
        lastTickTime = now

        stateElapsed += dt
        frameElapsed += dt

        // Advance sprite animation frame
        let frames = state.frames
        if frameElapsed >= state.frameDuration && frames.count > 1 {
            frameElapsed = 0
            frameIndex = (frameIndex + 1) % frames.count
            updateSpriteFrame()
        }

        // Occasional zZz while resting
        if state == .resting {
            zzzCooldown -= dt
            if zzzCooldown <= 0 {
                zzzCooldown = Double.random(in: 3.0...4.5)
                spawnParticle(
                    text: "zZz",
                    color: NSColor(calibratedRed: 0.82, green: 0.90, blue: 1.0, alpha: 1.0),
                    fontSize: 13
                )
            }
        }

        // Jump arc
        if state == .jumping {
            let progress = min(1.0, stateElapsed / max(0.01, stateDuration))
            gabiView.jumpOffsetY = CGFloat(sin(progress * .pi)) * 42.0
            if GabiPreferences.shared.roamEnabled {
                moveHorizontally(speed: 115.0 * walkDirection, dt: dt)
            }
        }

        // Chasing thrown tennis ball takes priority
        if isPerformingVoiceTask || state == .listening {
            // Let voice task / listening hold control calmly
        } else if ballController.isActive && state != .dragging {
            ballController.step(dt: dt)
            updateChaseBall(dt: dt)
        } else if GabiPreferences.shared.stayResting && state != .dragging {
            // Stay peacefully lying down without moving
            if state != .resting {
                transition(to: .resting, duration: 999_999)
            }
        } else if GabiPreferences.shared.followMouse,
                  state != .dragging, state != .happy, state != .barking, state != .jumping {
            updateFollowMouse(dt: dt)
        } else {
            // Autonomous movement when walking/running
            switch state {
            case .walking:
                if GabiPreferences.shared.roamEnabled {
                    moveHorizontally(speed: 78.0 * walkDirection, dt: dt)
                }
            case .running:
                if GabiPreferences.shared.roamEnabled {
                    moveHorizontally(speed: 175.0 * walkDirection, dt: dt)
                }
            default:
                break
            }

            // Pick next autonomous behavior when current state ends
            if state != .dragging && stateElapsed >= stateDuration {
                chooseNextAutonomousState()
            }
        }

        updateParticles(dt: dt)
        rescheduleTimer(interval: desiredTickInterval())
    }

    private func updateChaseBall(dt: TimeInterval) {
        let screen = currentScreenFrame()
        let gabiX = window.frame.midX
        let targetX = ballController.position.x
        let dx = targetX - gabiX

        gabiView.facingRight = dx >= 0
        walkDirection = dx >= 0 ? 1.0 : -1.0

        if state != .running {
            transition(to: .running, duration: 12.0)
        }

        // Gently descend toward the floor if Gabi was placed high up
        let floorOriginY = screen.minY + 12
        var origin = window.frame.origin
        let speed: CGFloat = 250.0
        if abs(dx) > 10 {
            let stepX = (dx > 0 ? 1.0 : -1.0) * min(abs(dx), speed * CGFloat(dt))
            origin.x += stepX
        }
        if abs(origin.y - floorOriginY) > 4 {
            let dy = floorOriginY - origin.y
            origin.y += (dy > 0 ? 1.0 : -1.0) * min(abs(dy), 180.0 * CGFloat(dt))
        }
        window.setFrameOrigin(origin)
        clampToScreen()

        // Catch the ball when close enough and ball is near floor level
        let distX = abs(window.frame.midX - ballController.position.x)
        let ballNearFloor = ballController.position.y <= screen.minY + 115
        if distX < 44 && ballNearFloor {
            ballController.hide()
            SoundManager.shared.playBark()
            transition(to: .jumping, duration: 0.72)
            spawnHearts(count: 3)
            spawnParticle(text: "🎾", color: NSColor.white, fontSize: 16)
        }
    }

    private func updateFollowMouse(dt: TimeInterval) {
        let mouse = NSEvent.mouseLocation
        let center = NSPoint(x: window.frame.midX, y: window.frame.minY + gabiView.spriteDrawSize * 0.45)
        let dx = mouse.x - center.x
        let dy = mouse.y - center.y
        let dist = hypot(dx, dy)

        if dist < 95 {
            if state != .sitting && state != .idle {
                transition(to: .sitting, duration: 4.0)
            }
            return
        }

        gabiView.facingRight = dx >= 0
        walkDirection = dx >= 0 ? 1.0 : -1.0

        let speed: CGFloat = dist > 260 ? 210.0 : 105.0
        let desiredState: GabiState = dist > 260 ? .running : .walking
        if state != desiredState {
            transition(to: desiredState, duration: 5.0)
        }

        let step = speed * CGFloat(dt)
        let nx = window.frame.origin.x + (dx / dist) * step
        let ny = window.frame.origin.y + (dy / dist) * step
        window.setFrameOrigin(NSPoint(x: nx, y: ny))
        clampToScreen()
    }

    private func chooseNextAutonomousState() {
        let canRoam = GabiPreferences.shared.roamEnabled
        let roll = Int.random(in: 0..<100)

        if canRoam {
            switch roll {
            case 0..<32:
                walkDirection = Bool.random() ? 1.0 : -1.0
                gabiView.facingRight = walkDirection > 0
                transition(to: .walking, duration: Double.random(in: 2.5...5.5))
            case 32..<46:
                walkDirection = Bool.random() ? 1.0 : -1.0
                gabiView.facingRight = walkDirection > 0
                transition(to: .running, duration: Double.random(in: 1.4...2.8))
            case 46..<64:
                transition(to: .sitting, duration: Double.random(in: 3.5...7.0))
            case 64..<80:
                transition(to: .resting, duration: Double.random(in: 7.0...14.0))
                zzzCooldown = 1.5
            case 80..<90:
                transition(to: .idle, duration: Double.random(in: 2.5...4.5))
            case 90..<96:
                triggerJump()
            default:
                triggerBark()
            }
        } else {
            switch roll {
            case 0..<35:
                transition(to: .sitting, duration: Double.random(in: 4.0...8.0))
            case 35..<68:
                transition(to: .resting, duration: Double.random(in: 8.0...15.0))
                zzzCooldown = 1.5
            case 68..<88:
                transition(to: .idle, duration: Double.random(in: 3.0...5.5))
            case 88..<95:
                triggerJump()
            default:
                triggerBark()
            }
        }
    }

    private func moveHorizontally(speed: CGFloat, dt: TimeInterval) {
        let screen = currentScreenFrame()
        var origin = window.frame.origin
        origin.x += speed * CGFloat(dt)

        let minX = screen.minX + 8
        let maxX = screen.maxX - window.frame.width - 8

        if origin.x <= minX {
            origin.x = minX
            walkDirection = 1.0
            gabiView.facingRight = true
        } else if origin.x >= maxX {
            origin.x = maxX
            walkDirection = -1.0
            gabiView.facingRight = false
        }

        window.setFrameOrigin(origin)
    }

    private func currentScreenFrame() -> NSRect {
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        for screen in NSScreen.screens {
            if screen.frame.contains(center) {
                return screen.visibleFrame
            }
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    }

    private func clampToScreen() {
        let vis = currentScreenFrame()
        var origin = window.frame.origin
        origin.x = max(vis.minX, min(origin.x, vis.maxX - window.frame.width))
        origin.y = max(vis.minY, min(origin.y, vis.maxY - window.frame.height))
        window.setFrameOrigin(origin)
    }

    private func updateSpriteFrame() {
        let frames = state.frames
        let idx = frameIndex % max(1, frames.count)
        gabiView.currentSprite = SpriteStore.shared.sprite(named: frames[idx])
    }

    // MARK: - Particles

    private func spawnHearts(count: Int) {
        let colors: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.32, blue: 0.48, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.68, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.40, blue: 0.35, alpha: 1.0)
        ]
        for i in 0..<count {
            let offsetX = CGFloat.random(in: -30...30)
            let offsetY = CGFloat(i) * 6.0
            let p = FloatingParticle(
                text: "♥",
                color: colors[i % colors.count],
                x: gabiView.bounds.midX + offsetX,
                y: gabiView.spriteDrawSize * 0.78 + offsetY,
                vx: CGFloat.random(in: -14...14),
                vy: CGFloat.random(in: 28...44),
                age: 0,
                lifetime: CGFloat.random(in: 1.0...1.5),
                fontSize: CGFloat.random(in: 15...21)
            )
            gabiView.particles.append(p)
        }
        rescheduleTimer(interval: desiredTickInterval())
    }

    private func spawnParticle(text: String, color: NSColor, fontSize: CGFloat) {
        let p = FloatingParticle(
            text: text,
            color: color,
            x: gabiView.bounds.midX + CGFloat.random(in: -12...18),
            y: gabiView.spriteDrawSize * 0.85,
            vx: CGFloat.random(in: -6...10),
            vy: 26,
            age: 0,
            lifetime: 1.35,
            fontSize: fontSize
        )
        gabiView.particles.append(p)
        rescheduleTimer(interval: desiredTickInterval())
    }

    private func updateParticles(dt: TimeInterval) {
        guard !gabiView.particles.isEmpty else { return }
        let step = CGFloat(dt)
        gabiView.particles = gabiView.particles.compactMap { var p = $0
            p.age += step
            if p.age >= p.lifetime { return nil }
            p.x += p.vx * step
            p.y += p.vy * step
            return p
        }
    }

    // MARK: - Voice Command Router

    private func handleVoiceCommand(_ rawTranscript: String) {
        let lower = rawTranscript
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip optional wake word "gabi" (and common phonetic transcriptions)
        var cmd = lower
        for prefix in [
            "gabi ", "gaby ", "gavi ", "gabi, ", "gaby, ", "gavi, ",
            "oye gabi ", "oye gaby ", "oye gavi ",
            "hey gabi ", "hey gaby ", "hola gabi "
        ] {
            if cmd.hasPrefix(prefix) {
                cmd = String(cmd.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // 0. Check user's custom commands.json first (reloads live on every command!)
        if let custom = CommandStore.shared.match(normalizedCommand: cmd) {
            executeCustomCommand(custom)
            return
        }

        // 1. Gabi pet commands
        if cmd.contains("esquina") || cmd.contains("rincon") || cmd.contains("apartate") || cmd.contains("no molestes") {
            goToCorner()
            return
        }
        if cmd.contains("tumbate") || cmd.contains("acuestate") || cmd.contains("duerme") || cmd.contains("quieto") {
            showTemporaryBubble("💤 ¡A dormir!")
            setStayResting(true)
            return
        }
        if cmd.contains("levantate") || cmd.contains("despierta") || cmd.contains("arriba") || cmd.contains("pasea") {
            showTemporaryBubble("🐾 ¡Despierto!")
            setStayResting(false)
            triggerJump()
            return
        }
        if cmd.contains("pelota") || cmd.contains("juega") {
            showTemporaryBubble("🎾 ¡Voy!")
            throwBall()
            return
        }
        if cmd.contains("salta") || cmd.contains("brinca") {
            showTemporaryBubble("✨ ¡Hop!")
            triggerJump()
            return
        }
        if cmd.contains("ladra") || cmd.contains("habla") || cmd.contains("guau") {
            triggerBark()
            return
        }
        if cmd.contains("ven") || cmd.contains("sigueme") {
            showTemporaryBubble("🐾 ¡Voy contigo!")
            setStayResting(false)
            centerOnScreen()
            return
        }
        if cmd.contains("guapo") || cmd.contains("buen chico") || cmd.contains("carino") || cmd.contains("te quiero") {
            showTemporaryBubble("❤️ ¡Guau!")
            triggerBark()
            spawnHearts(count: 5)
            return
        }

        // 2. Search commands: "busca X en youtube" / "busca X en google" / "busca X"
        if cmd.hasPrefix("busca ") || cmd.hasPrefix("buscar ") || cmd.hasPrefix("pon ") {
            var query = cmd
            for p in ["busca ", "buscar ", "pon "] {
                if query.hasPrefix(p) { query = String(query.dropFirst(p.count)); break }
            }
            if query.contains(" en youtube") {
                let q = query.replacingOccurrences(of: " en youtube", with: "").trimmingCharacters(in: .whitespaces)
                let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
                let url = URL(string: "https://www.youtube.com/results?search_query=\(enc)")!
                runToBrowserAndType(label: "YouTube: \(q)", textToType: "https://www.youtube.com/results?search_query=\(enc)", fallbackURL: url)
                return
            }
            let q = query.replacingOccurrences(of: " en google", with: "").trimmingCharacters(in: .whitespaces)
            let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            let url = URL(string: "https://www.google.com/search?q=\(enc)")!
            runToBrowserAndType(label: "Google: \(q)", textToType: q, fallbackURL: url)
            return
        }

        // 3. Open website or app: "abre X" / "abrir X"
        if cmd.hasPrefix("abre ") || cmd.hasPrefix("abrir ") {
            let target = cmd
                .replacingOccurrences(of: "abre ", with: "")
                .replacingOccurrences(of: "abrir ", with: "")
                .trimmingCharacters(in: .whitespaces)

            let knownSites: [String: (String, String)] = [
                "youtube": ("youtube.com", "https://www.youtube.com"),
                "google": ("google.com", "https://www.google.com"),
                "twitch": ("twitch.tv", "https://www.twitch.tv"),
                "instagram": ("instagram.com", "https://www.instagram.com"),
                "twitter": ("x.com", "https://x.com"),
                "x": ("x.com", "https://x.com"),
                "gmail": ("mail.google.com", "https://mail.google.com"),
                "chatgpt": ("chatgpt.com", "https://chatgpt.com"),
                "github": ("github.com", "https://github.com"),
                "netflix": ("netflix.com", "https://www.netflix.com"),
                "amazon": ("amazon.es", "https://www.amazon.es"),
                "reddit": ("reddit.com", "https://www.reddit.com"),
                "wikipedia": ("es.wikipedia.org", "https://es.wikipedia.org")
            ]

            for (key, site) in knownSites {
                if target.contains(key), let url = URL(string: site.1) {
                    runToBrowserAndType(label: "🌐 \(site.0)", textToType: site.0, fallbackURL: url)
                    return
                }
            }

            // Try opening a Mac application
            if BrowserTyper.shared.openApp(named: target) {
                SoundManager.shared.playBark()
                showTemporaryBubble("🚀 \(target.capitalized)")
                triggerJump()
                spawnHearts(count: 2)
                return
            }

            // Fallback: type it into the browser search bar!
            let enc = target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? target
            let url = URL(string: "https://www.google.com/search?q=\(enc)")!
            runToBrowserAndType(label: "🔎 \(target)", textToType: target, fallbackURL: url)
            return
        }

        // Fallback if user just said a site name like "youtube"
        if cmd.contains("youtube"), let url = URL(string: "https://www.youtube.com") {
            runToBrowserAndType(label: "🌐 youtube.com", textToType: "youtube.com", fallbackURL: url)
            return
        }

        // Fallback: if Gemini AI is configured, ask Gabi's AI!
        if GabiAI.shared.isConfigured {
            gabiView.statusBubbleText = "🧠 Pensando..."
            GabiAI.shared.ask(rawTranscript) { [weak self] reply in
                guard let self = self else { return }
                if let reply = reply {
                    SoundManager.shared.playBark()
                    self.showTemporaryBubble(reply, seconds: 6.5)
                    self.spawnHearts(count: 2)
                    if !GabiPreferences.shared.stayResting {
                        self.transition(to: .happy, duration: 2.0)
                    }
                } else {
                    self.showTemporaryBubble("🐾 No pude conectar con la IA", seconds: 2.5)
                }
            }
            return
        }

        showTemporaryBubble("🐾 \"\(rawTranscript)\"", seconds: 2.4)
        triggerBark()
    }

    private func executeCustomCommand(_ custom: CustomVoiceCommand) {
        if custom.ladrar ?? true {
            SoundManager.shared.playBark()
        }
        if custom.corazones ?? false {
            spawnHearts(count: 5)
        }
        let bubble = custom.mensaje ?? "🐾 ¡Voy!"
        showTemporaryBubble(bubble, seconds: 2.8)

        switch custom.tipo.lowercased() {
        case "url":
            guard let url = URL(string: custom.valor) else { return }
            if custom.teclear ?? false {
                runToBrowserAndType(label: bubble, textToType: custom.valor, fallbackURL: url)
            } else {
                triggerJump()
                NSWorkspace.shared.open(url)
            }
        case "buscar":
            let enc = custom.valor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? custom.valor
            if let url = URL(string: "https://www.google.com/search?q=\(enc)") {
                runToBrowserAndType(label: bubble, textToType: custom.valor, fallbackURL: url)
            }
        case "app":
            if BrowserTyper.shared.openApp(named: custom.valor) {
                triggerJump()
            } else {
                showTemporaryBubble("No encontré \(custom.valor)", seconds: 2.5)
            }
        case "accion":
            switch custom.valor.lowercased() {
            case "tumbarse", "acostarse", "dormir": setStayResting(true)
            case "levantarse", "despertar": setStayResting(false)
            case "pelota": throwBall()
            case "saltar": triggerJump()
            case "ladrar": triggerBark()
            case "acariciar": triggerPet()
            case "esquina": goToCorner()
            default: triggerHappy()
            }
        default:
            triggerHappy()
        }
    }

    /// Animates Gabi bounding up to the top of the screen near the browser search bar,
    /// typing the text into the browser, celebrating, and returning gently!
    private func runToBrowserAndType(label: String, textToType: String, fallbackURL: URL) {
        isPerformingVoiceTask = true
        let originalOrigin = window.frame.origin
        let screen = currentScreenFrame()
        let barOrigin = NSPoint(
            x: screen.midX - window.frame.width / 2,
            y: screen.maxY - window.frame.height - 16
        )

        gabiView.facingRight = barOrigin.x >= originalOrigin.x
        SoundManager.shared.playBark()
        showTemporaryBubble("⌨️ \(label)", seconds: 3.5)
        transition(to: .running, duration: 5.0)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.55
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(barOrigin)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.transition(to: .happy, duration: 4.0)
            BrowserTyper.shared.typeInBrowser(textToType: textToType, fallbackURL: fallbackURL) { [weak self] in
                guard let self = self else { return }
                self.spawnHearts(count: 3)
                self.transition(to: .running, duration: 2.0)
                self.gabiView.facingRight = originalOrigin.x >= barOrigin.x

                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.65
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.window.animator().setFrameOrigin(originalOrigin)
                }, completionHandler: { [weak self] in
                    guard let self = self else { return }
                    self.isPerformingVoiceTask = false
                    self.gabiView.statusBubbleText = nil
                    self.transition(to: GabiPreferences.shared.stayResting ? .resting : .sitting, duration: 3.5)
                })
            }
        })
    }

    // MARK: - GabiViewDelegate

    func gabiViewDidClick(_ view: GabiView) {
        triggerPet()
    }

    func gabiViewDidDoubleClick(_ view: GabiView) {
        triggerJump()
        spawnHearts(count: 2)
    }

    func gabiViewDidStartDrag(_ view: GabiView) {
        transition(to: .dragging, duration: 999)
    }

    func gabiViewDidDrag(_ view: GabiView, delta: NSPoint) {
        var origin = window.frame.origin
        origin.x += delta.x
        origin.y += delta.y
        window.setFrameOrigin(origin)
        if abs(delta.x) > 1.5 {
            gabiView.facingRight = delta.x > 0
        }
    }

    func gabiViewDidEndDrag(_ view: GabiView) {
        clampToScreen()
        if GabiPreferences.shared.stayResting {
            transition(to: .resting, duration: 999_999)
        } else {
            transition(to: .sitting, duration: 3.0)
        }
        spawnHearts(count: 1)
    }

    func gabiViewContextMenu(_ view: GabiView) -> NSMenu? {
        return contextMenuProvider?()
    }
}
