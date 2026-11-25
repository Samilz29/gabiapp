import Cocoa

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var gabiController: GabiWindowController?
    private var statusMenuItem: NSMenuItem?

    init(gabiController: GabiWindowController) {
        self.gabiController = gabiController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            if let pawImage = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Gabi") {
                pawImage.isTemplate = true
                button.image = pawImage
                button.toolTip = "Gabi"
            } else {
                button.title = "🐾"
            }
        }

        statusItem.menu = buildMenu()

        gabiController.onStateChange = { [weak self] newState in
            self?.statusMenuItem?.title = newState.statusDescription
        }
        gabiController.onPreferencesChange = { [weak self] in
            guard let self = self else { return }
            self.statusItem.menu = self.buildMenu()
        }
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let titleItem = NSMenuItem(
            title: gabiController?.state.statusDescription ?? "Gabi 🐾",
            action: nil,
            keyEquivalent: ""
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        self.statusMenuItem = titleItem

        menu.addItem(NSMenuItem.separator())

        let voiceItem = NSMenuItem(title: "🎤 Hablar con Gabi (⌥G)", action: #selector(speakToGabi), keyEquivalent: "")
        voiceItem.target = self
        menu.addItem(voiceItem)

        let editCmdsItem = NSMenuItem(title: "📝 Editar órdenes personalizadas...", action: #selector(editCustomCommands), keyEquivalent: "")
        editCmdsItem.target = self
        menu.addItem(editCmdsItem)

        let aiLabel = GabiAI.shared.isConfigured ? "🧠 IA de Gabi (Gemini ✓)..." : "🧠 Configurar IA (Gemini)..."
        let aiItem = NSMenuItem(title: aiLabel, action: #selector(configureAI), keyEquivalent: "")
        aiItem.target = self
        menu.addItem(aiItem)

        let petItem = NSMenuItem(title: "❤️ Acariciar a Gabi", action: #selector(petGabi), keyEquivalent: "")
        petItem.target = self
        menu.addItem(petItem)

        let ballItem = NSMenuItem(title: "🎾 Lanzar pelota", action: #selector(throwBall), keyEquivalent: "")
        ballItem.target = self
        menu.addItem(ballItem)

        let jumpItem = NSMenuItem(title: "✨ Hacer saltar", action: #selector(jumpGabi), keyEquivalent: "")
        jumpItem.target = self
        menu.addItem(jumpItem)

        let barkItem = NSMenuItem(title: "🐾 Ladrar", action: #selector(barkGabi), keyEquivalent: "")
        barkItem.target = self
        menu.addItem(barkItem)

        menu.addItem(NSMenuItem.separator())

        let stayRestItem = NSMenuItem(title: "💤 Quedarse acostado (quieto)", action: #selector(toggleStayResting), keyEquivalent: "")
        stayRestItem.target = self
        stayRestItem.state = GabiPreferences.shared.stayResting ? .on : .off
        menu.addItem(stayRestItem)

        let cornerItem = NSMenuItem(title: "↘️ Ir a la esquina (sin molestar)", action: #selector(sendToCorner), keyEquivalent: "")
        cornerItem.target = self
        menu.addItem(cornerItem)

        let roamItem = NSMenuItem(title: "Pasear por la pantalla", action: #selector(toggleRoam), keyEquivalent: "")
        roamItem.target = self
        roamItem.state = GabiPreferences.shared.roamEnabled ? .on : .off
        menu.addItem(roamItem)

        let followItem = NSMenuItem(title: "Seguir al ratón", action: #selector(toggleFollowMouse), keyEquivalent: "")
        followItem.target = self
        followItem.state = GabiPreferences.shared.followMouse ? .on : .off
        menu.addItem(followItem)

        menu.addItem(NSMenuItem.separator())

        let soundToggle = NSMenuItem(title: "🔊 Sonido al ladrar", action: #selector(toggleSound), keyEquivalent: "")
        soundToggle.target = self
        soundToggle.state = GabiPreferences.shared.soundEnabled ? .on : .off
        menu.addItem(soundToggle)

        let audioLabel = SoundManager.shared.hasCustomBark
            ? "🎵 Cambiar audio de ladrido..."
            : "🎵 Elegir audio de ladrido..."
        let chooseAudioItem = NSMenuItem(title: audioLabel, action: #selector(chooseBarkAudio), keyEquivalent: "")
        chooseAudioItem.target = self
        menu.addItem(chooseAudioItem)

        if SoundManager.shared.hasCustomBark {
            let removeAudioItem = NSMenuItem(title: "Quitar audio personalizado", action: #selector(removeBarkAudio), keyEquivalent: "")
            removeAudioItem.target = self
            menu.addItem(removeAudioItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Size submenu
        let sizeMenu = NSMenu()
        let currentSize = GabiPreferences.shared.size
        for size in GabiSize.allCases {
            let item = NSMenuItem(title: size.label, action: #selector(selectSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = (size == currentSize) ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeRoot = NSMenuItem(title: "Tamaño de Gabi", action: nil, keyEquivalent: "")
        sizeRoot.submenu = sizeMenu
        menu.addItem(sizeRoot)

        if !BrowserTyper.shared.hasAccessibilityPermission {
            let axItem = NSMenuItem(title: "⚙️ Permitir teclear en navegador...", action: #selector(requestAccessibility), keyEquivalent: "")
            axItem.target = self
            menu.addItem(axItem)
        }

        let centerItem = NSMenuItem(title: "Traer al centro", action: #selector(centerGabi), keyEquivalent: "")
        centerItem.target = self
        menu.addItem(centerItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Salir", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func speakToGabi() {
        gabiController?.toggleVoiceListening()
    }

    @objc private func editCustomCommands() {
        CommandStore.shared.openInEditor()
    }

    @objc private func configureAI() {
        GabiAI.shared.promptForApiKey { [weak self] _ in
            guard let self = self else { return }
            self.statusItem.menu = self.buildMenu()
        }
    }

    @objc private func requestAccessibility() {
        BrowserTyper.shared.requestAccessibilityPermission()
    }

    @objc private func petGabi() {
        gabiController?.triggerPet()
    }

    @objc private func throwBall() {
        gabiController?.throwBall()
    }

    @objc private func jumpGabi() {
        gabiController?.triggerJump()
    }

    @objc private func barkGabi() {
        gabiController?.triggerBark()
    }

    @objc private func toggleStayResting() {
        let next = !GabiPreferences.shared.stayResting
        gabiController?.setStayResting(next)
    }

    @objc private func sendToCorner() {
        gabiController?.goToCorner()
    }

    @objc private func toggleRoam() {
        let next = !GabiPreferences.shared.roamEnabled
        GabiPreferences.shared.roamEnabled = next
        statusItem.menu = buildMenu()
    }

    @objc private func toggleFollowMouse() {
        let next = !GabiPreferences.shared.followMouse
        GabiPreferences.shared.followMouse = next
        if next && GabiPreferences.shared.stayResting {
            GabiPreferences.shared.stayResting = false
        }
        statusItem.menu = buildMenu()
    }

    @objc private func toggleSound() {
        GabiPreferences.shared.soundEnabled = !GabiPreferences.shared.soundEnabled
        statusItem.menu = buildMenu()
    }

    @objc private func chooseBarkAudio() {
        SoundManager.shared.chooseCustomBarkAudio { [weak self] saved in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.statusItem.menu = self.buildMenu()
                if saved {
                    self.gabiController?.triggerBark()
                }
            }
        }
    }

    @objc private func removeBarkAudio() {
        SoundManager.shared.removeCustomBark()
        statusItem.menu = buildMenu()
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let size = GabiSize(rawValue: raw) {
            gabiController?.applySize(size)
            statusItem.menu = buildMenu()
        }
    }

    @objc private func centerGabi() {
        gabiController?.centerOnScreen()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
