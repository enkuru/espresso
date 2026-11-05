import AppKit
import SwiftUI

/// The menu bar item: left-click opens the panel, right-click or Control-click starts or stops a session.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: EspressoModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var frameTimer: Timer?
    private var frame = 0

    init(model: EspressoModel) {
        self.model = model
        super.init()

        let controller = NSHostingController(rootView: PanelView(model: model))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageRight
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.setAccessibilityLabel("Espresso")
        }
        observeModel()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover.performClose(nil)
            model.toggle()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
            sender.highlight(true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        item.button?.highlight(false)
    }

    // MARK: Icon

    private func observeModel() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeModel() }
        }
    }

    private var animates: Bool {
        model.session != nil && model.animateIcon && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func updateButton() {
        guard let button = item.button else { return }
        if animates {
            startFrames()
        } else {
            stopFrames()
        }
        button.image = currentImage()
        button.title = model.menuBarCountdown.map { "\($0) " } ?? ""
        button.toolTip = "Espresso · \(model.statusLine)"
    }

    private func currentImage() -> NSImage {
        let active = model.session != nil
        let steam: CupArt.Steam
        if !active {
            steam = .hidden
        } else if frameTimer != nil {
            steam = .rising(phase: Double(frame) / Double(CupArt.frameCount))
        } else {
            steam = .still
        }
        return CupArt.menuBarImage(filled: active, steam: steam, lidDot: model.closedLidState == .on)
    }

    private func startFrames() {
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: CupArt.cycleSeconds / Double(CupArt.frameCount), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func advanceFrame() {
        frame = (frame + 1) % CupArt.frameCount
        item.button?.image = currentImage()
    }

    private func stopFrames() {
        frameTimer?.invalidate()
        frameTimer = nil
        frame = 0
    }
}
