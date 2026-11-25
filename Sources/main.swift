import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var gabiController: GabiWindowController!
    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        gabiController = GabiWindowController()
        statusBarController = StatusBarController(gabiController: gabiController)
        gabiController.contextMenuProvider = { [weak self] in
            self?.statusBarController.buildMenu() ?? NSMenu()
        }
        gabiController.showAndStart()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Menu bar + floating pet without cluttering the Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
