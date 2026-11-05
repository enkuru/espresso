import AppKit
import SwiftUI

/// Renders the app icon and preview images. Used by the `espresso-render` build tool, never by the app.
@MainActor
public enum Artwork {
    private static let espressoTop = CGColor(srgbRed: 0.604, green: 0.353, blue: 0.188, alpha: 1)
    private static let espressoBottom = CGColor(srgbRed: 0.369, green: 0.196, blue: 0.086, alpha: 1)

    // MARK: App icon

    public static func writeIconSet(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            try png(appIconPixels: points).write(to: folder.appendingPathComponent("icon_\(points)x\(points).png"))
            try png(appIconPixels: points * 2).write(to: folder.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
    }

    private static func png(appIconPixels pixels: Int) throws -> Data {
        try renderPNG(width: pixels, height: pixels) { context in
            let scale = CGFloat(pixels) / 1024
            context.scaleBy(x: scale, y: scale)

            let tile = CGPath(
                roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                cornerWidth: 185,
                cornerHeight: 185,
                transform: nil
            )
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
            context.addPath(tile)
            context.setFillColor(espressoBottom)
            context.fillPath()
            context.restoreGState()

            context.saveGState()
            context.addPath(tile)
            context.clip()
            let gradient = CGGradient(colorsSpace: nil, colors: [espressoTop, espressoBottom] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
            context.restoreGState()

            let cupSize: CGFloat = 560
            let unit = cupSize / 24
            context.translateBy(x: 512 - 11.85 * unit, y: 512 - 12 * unit)
            CupArt.draw(
                in: context,
                size: cupSize,
                filled: true,
                steam: .still,
                lidDot: false,
                color: CGColor(srgbRed: 1, green: 0.976, blue: 0.945, alpha: 1)
            )
        }
    }

    // MARK: Previews

    public static func writePreviews(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try menuBarSheet().write(to: folder.appendingPathComponent("menu-bar-icon.png"))

        let suiteName = "espresso-render-preview"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("espresso-preview.flag")

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let idle = EspressoModel(defaults: defaults, lidFlag: flag)
        idle.keepScreenOn = true
        idle.closedLid = false
        try panelPNG(idle, dark: false).write(to: folder.appendingPathComponent("panel-off-light.png"))

        // Set the lid state before the toggle, so the preview never asks for a password.
        let awake = EspressoModel(defaults: defaults, lidFlag: flag)
        awake.closedLidState = .on
        awake.session = Session(length: .timed(seconds: 7_200), startedAt: Date().addingTimeInterval(-1_085))
        awake.now = Date()
        awake.closedLid = true
        awake.lowBatteryPercent = 30
        try panelPNG(awake, dark: false).write(to: folder.appendingPathComponent("panel-awake-light.png"))
        try panelPNG(awake, dark: true).write(to: folder.appendingPathComponent("panel-awake-dark.png"))
        awake.session = nil
    }

    private static func panelPNG(_ model: EspressoModel, dark: Bool) throws -> Data {
        let root = PanelView(model: model)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(20)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.backgroundColor = dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.86, alpha: 1)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        window.displayIfNeeded()

        guard let contentView = window.contentView,
              let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    /// The four menu bar states on a light and a dark bar, then the steam frames enlarged.
    private static func menuBarSheet() throws -> Data {
        let scale: CGFloat = 4
        let states: [(label: String, filled: Bool, steam: CupArt.Steam, dot: Bool, time: String?)] = [
            ("Off", false, .hidden, false, nil),
            ("Awake", true, .rising(phase: 0.55), false, nil),
            ("Timed", true, .rising(phase: 0.55), false, "1:42"),
            ("Lid closed", true, .rising(phase: 0.55), true, nil),
        ]
        let cell: CGFloat = 76
        let frames = 6
        let width = Int(CGFloat(states.count) * cell * scale)
        let height = Int((22 + 22 + 64) * scale)

        return try renderPNG(width: width, height: height) { context in
            context.scaleBy(x: scale, y: scale)
            for (row, dark) in [false, true].enumerated() {
                let top = CGFloat(row) * 22
                context.setFillColor(dark ? CGColor(gray: 0.13, alpha: 1) : CGColor(gray: 0.96, alpha: 1))
                context.fill(CGRect(x: 0, y: top, width: CGFloat(width) / scale, height: 22))
                let ink = dark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 0.85)
                for (index, state) in states.enumerated() {
                    var x = CGFloat(index) * cell + 12
                    if let time = state.time {
                        drawText(time, at: CGPoint(x: x, y: top + 4), size: 12, color: ink, in: context)
                        x += 28
                    }
                    context.saveGState()
                    context.translateBy(x: x, y: top + 2)
                    CupArt.draw(in: context, size: 18, filled: state.filled, steam: state.steam, lidDot: state.dot, color: ink)
                    context.restoreGState()
                    if !dark {
                        drawText(state.label, at: CGPoint(x: x + 22, y: top + 6), size: 8, color: CGColor(gray: 0.45, alpha: 1), in: context)
                    }
                }
            }

            let top: CGFloat = 44
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: top, width: CGFloat(width) / scale, height: 64))
            let step = CGFloat(width) / scale / CGFloat(frames)
            for frame in 0..<frames {
                let phase = Double(frame) / Double(frames)
                context.saveGState()
                context.translateBy(x: CGFloat(frame) * step + (step - 40) / 2, y: top + 6)
                CupArt.draw(
                    in: context,
                    size: 40,
                    filled: true,
                    steam: .rising(phase: phase),
                    lidDot: false,
                    color: CGColor(srgbRed: 0.478, green: 0.263, blue: 0.125, alpha: 1)
                )
                context.restoreGState()
                drawText(
                    "frame \(frame * CupArt.frameCount / frames)",
                    at: CGPoint(x: CGFloat(frame) * step + step / 2 - 14, y: top + 50),
                    size: 8,
                    color: CGColor(gray: 0.45, alpha: 1),
                    in: context
                )
            }
        }
    }

    // MARK: Drawing helpers

    /// Draws into a bitmap whose coordinates point down, like the cup grid.
    private static func renderPNG(width: Int, height: Int, draw: (CGContext) -> Void) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
            throw CocoaError(.fileWriteUnknown)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(context)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private static func drawText(_ text: String, at point: CGPoint, size: CGFloat, color: CGColor, in context: CGContext) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        let string = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor(cgColor: color) ?? .black,
        ])
        let line = CTLineCreateWithAttributedString(string)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: point.x, y: point.y + font.ascender)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
