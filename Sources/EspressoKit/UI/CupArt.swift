import AppKit

/// The coffee cup, drawn on a 24-unit grid with y pointing down. The menu bar icon, the panel's hero cup
/// and the app icon all draw from here.
enum CupArt {
    enum Steam: Equatable {
        case hidden
        case still
        /// `phase` runs from 0 to 1 over one cycle.
        case rising(phase: Double)
    }

    static let frameCount = 24
    static let cycleSeconds = 1.8
    static let lineWidth: CGFloat = 1.7

    private static let wispStarts = [CGPoint(x: 8, y: 3.5), CGPoint(x: 11.5, y: 2.5), CGPoint(x: 15, y: 3.5)]

    static func draw(
        in context: CGContext,
        size: CGFloat,
        filled: Bool,
        steam: Steam,
        lidDot: Bool,
        color: CGColor
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.scaleBy(x: size / 24, y: size / 24)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color)
        context.setFillColor(color)

        let body = bodyPath()
        if filled {
            context.addPath(body)
            context.fillPath()
        }
        context.addPath(body)
        context.strokePath()

        context.addPath(handlePath())
        context.strokePath()

        context.move(to: CGPoint(x: 3, y: 21.5))
        context.addLine(to: CGPoint(x: 20, y: 21.5))
        context.strokePath()

        drawSteam(steam, in: context)

        if lidDot {
            context.fillEllipse(in: CGRect(x: 20.5 - 2.4, y: 4.5 - 2.4, width: 4.8, height: 4.8))
        }
    }

    static func menuBarImage(filled: Bool, steam: Steam, lidDot: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, size: 18, filled: filled, steam: steam, lidDot: lidDot, color: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Paths

    private static func bodyPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4, y: 9.5))
        path.addLine(to: CGPoint(x: 17, y: 9.5))
        path.addLine(to: CGPoint(x: 17, y: 14))
        path.addArc(center: CGPoint(x: 12, y: 14), radius: 5, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: 9, y: 19))
        path.addArc(center: CGPoint(x: 9, y: 14), radius: 5, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        path.closeSubpath()
        return path
    }

    private static func handlePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 17, y: 11))
        path.addLine(to: CGPoint(x: 18.3, y: 11))
        path.addArc(center: CGPoint(x: 18.3, y: 13.4), radius: 2.4, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        path.addLine(to: CGPoint(x: 17, y: 15.8))
        return path
    }

    private static func drawSteam(_ steam: Steam, in context: CGContext) {
        for (index, start) in wispStarts.enumerated() {
            let (rise, alpha) = wispOffset(steam, index: index)
            guard alpha > 0 else { continue }

            context.saveGState()
            context.setAlpha(alpha)
            context.move(to: CGPoint(x: start.x, y: start.y + rise))
            context.addCurve(
                to: CGPoint(x: start.x, y: start.y + rise + 3.4),
                control1: CGPoint(x: start.x - 1, y: start.y + rise + 1.2),
                control2: CGPoint(x: start.x + 1, y: start.y + rise + 2.2)
            )
            context.strokePath()
            context.restoreGState()
        }
    }

    /// Each wisp rises 5 units while it fades in then out, a third of a cycle after the one before it.
    static func wispOffset(_ steam: Steam, index: Int) -> (rise: CGFloat, alpha: CGFloat) {
        switch steam {
        case .hidden:
            return (0, 0)
        case .still:
            return (0, 1)
        case .rising(let phase):
            var p = (phase - Double(index) / 3).truncatingRemainder(dividingBy: 1)
            if p < 0 { p += 1 }
            let eased = p * p * (3 - 2 * p)
            let alpha = p < 0.35 ? p / 0.35 : 1 - (p - 0.35) / 0.65
            return (CGFloat(2 - 5 * eased), CGFloat(alpha))
        }
    }
}
