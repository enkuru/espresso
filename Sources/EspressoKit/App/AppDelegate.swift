import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = EspressoModel()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.prepareAfterLaunch()
        statusItem = StatusItemController(model: model)
    }

    /// Releases the holds and turns lid-close sleep back on. If Espresso is killed instead, macOS drops the
    /// holds and the lid watchdog restores sleep.
    func applicationWillTerminate(_ notification: Notification) {
        model.stop(reason: nil)
    }
}

@MainActor
public func runEspresso() -> Never {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
    exit(0)
}
