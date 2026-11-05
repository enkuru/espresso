import SwiftUI

extension Color {
    static let espresso = Color(nsColor: NSColor(name: "espresso") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.627, green: 0.380, blue: 0.227, alpha: 1)
            : NSColor(srgbRed: 0.478, green: 0.263, blue: 0.125, alpha: 1)
    })
}

struct PanelView: View {
    @Bindable var model: EspressoModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let durations: [(label: String, seconds: Int?)] = [
        ("∞", nil), ("30m", 1_800), ("1h", 3_600), ("2h", 7_200), ("4h", 14_400), ("8h", 28_800),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.session != nil {
                activity
            }
            durationChips
            untilChips
            tiles
            notes
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: Header

    private var isActive: Bool { model.session != nil }

    private var header: some View {
        HStack(spacing: 12) {
            CupView(
                active: isActive,
                animating: isActive && model.animateIcon && !reduceMotion,
                lidDot: model.closedLidState == .on
            )
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("Espresso")
                    .font(.system(size: 15, weight: .semibold))
                Text(model.statusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Toggle("Keep awake", isOn: Binding(
                get: { model.session != nil },
                set: { $0 ? model.start(.indefinitely) : model.stop(reason: nil) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(.espresso)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = model.progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(Color.espresso)
                            .frame(width: max(4, proxy.size.width * progress))
                    }
                }
                .frame(height: 4)
                .animation(.linear(duration: 1), value: progress)
            }
            if let holding = model.holdingLine {
                Text(holding)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Session pickers

    private var durationChips: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel("Keep awake for")
            HStack(spacing: 6) {
                ForEach(Self.durations, id: \.label) { duration in
                    Button(duration.label) {
                        model.start(duration.seconds.map { .timed(seconds: $0) } ?? .indefinitely)
                    }
                    .buttonStyle(ChipStyle(selected: isSelected(duration.seconds)))
                    .help(duration.seconds == nil ? "Until you turn it off" : "For \(duration.label)")
                }
            }
        }
    }

    private func isSelected(_ seconds: Int?) -> Bool {
        switch (model.session?.length, seconds) {
        case (.indefinitely, nil): true
        case (.timed(let current), let wanted?): current == wanted
        default: false
        }
    }

    private var untilChips: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel("Or until")
            HStack(spacing: 6) {
                appMenu
                Button {
                    model.start(.untilDownloadsFinish)
                } label: {
                    Label("Downloads finish", systemImage: "arrow.down.circle")
                }
                .buttonStyle(ChipStyle(selected: model.session?.length == .untilDownloadsFinish))
            }
        }
    }

    private var watchedAppName: String? {
        if case .untilAppQuits(_, let name) = model.session?.length { name } else { nil }
    }

    private var appMenu: some View {
        Menu {
            if model.runningApps.isEmpty {
                Text("No apps running")
            }
            ForEach(model.runningApps) { app in
                Button {
                    model.start(.untilAppQuits(pid: app.pid, name: app.name))
                } label: {
                    Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                }
            }
        } label: {
            Label(watchedAppName.map { "\($0) quits" } ?? "An app quits", systemImage: "app.badge.checkmark")
        }
        .menuStyle(.button)
        .buttonStyle(ChipStyle(selected: watchedAppName != nil))
        .menuIndicator(.hidden)
    }

    // MARK: Options

    private var tiles: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Tile(
                    title: "Screen on",
                    detail: model.keepScreenOn ? "Display stays on" : "Display may sleep",
                    symbol: "display",
                    isOn: $model.keepScreenOn
                )
                Tile(title: "Lid closed", detail: lidDetail, symbol: "laptopcomputer", isOn: $model.closedLid)
            }
            GridRow {
                batteryTile
                Tile(
                    title: "Animate icon",
                    detail: reduceMotion ? "Reduce Motion is on" : "Steam rises",
                    symbol: "cup.and.saucer",
                    isOn: $model.animateIcon
                )
            }
        }
    }

    private static let batteryLevels = [5, 10, 15, 20, 25, 30, 40, 50]

    /// Opens a menu instead of toggling: pick the level, or turn the stop off.
    private var batteryTile: some View {
        let face = TileFace(
            title: model.stopOnLowBattery ? "Stop at \(model.lowBatteryPercent)%" : "Battery stop",
            detail: model.stopOnLowBattery ? "When on battery" : "Off",
            symbol: "battery.25percent",
            isOn: model.stopOnLowBattery,
            opensMenu: true
        )
        return Menu {
            ForEach(Self.batteryLevels, id: \.self) { level in
                Toggle("Stop at \(level)%", isOn: Binding(
                    get: { model.stopOnLowBattery && model.lowBatteryPercent == level },
                    set: { _ in
                        model.lowBatteryPercent = level
                        model.stopOnLowBattery = true
                    }
                ))
            }
            Divider()
            Toggle("Don't stop", isOn: Binding(
                get: { !model.stopOnLowBattery },
                set: { _ in model.stopOnLowBattery = false }
            ))
        } label: {
            Text(face.title)
        }
        .menuStyle(.button)
        .buttonStyle(TileMenuStyle(face: face))
        .menuIndicator(.hidden)
        .help("Stop the session when the battery drops to this level on battery power")
        .accessibilityValue(model.stopOnLowBattery ? "\(model.lowBatteryPercent)%" : "Off")
    }

    private var lidDetail: String {
        switch model.closedLidState {
        case .waitingForPassword: "Waiting for password"
        case .on: "Active now"
        case .failed: "Couldn't turn on"
        case .off: model.closedLid ? "During sessions" : "Sleeps on close"
        }
    }

    // MARK: Notes

    @ViewBuilder
    private var notes: some View {
        if case .failed(let message) = model.closedLidState {
            Note(symbol: "exclamationmark.triangle", text: "Lid closed mode is off: \(message)")
        } else if model.closedLid {
            Note(symbol: "lock", text: model.hasPasswordlessRule
                ? "Uses your sudo rule, so no password. If Espresso quits or crashes, your Mac sleeps on close again. Don't run it in a bag."
                : "Asks for your admin password once per session. If Espresso quits or crashes, your Mac sleeps on close again. Don't run it in a bag.")
        }
        if model.sleepDisabledOutsideSession {
            Note(symbol: "exclamationmark.triangle", text: model.restoreError ?? "Sleep on lid close is turned off system-wide, outside Espresso.") {
                Button("Restore") { model.restoreSleep() }
                    .controlSize(.small)
            }
        }
        if model.noDownloadsFound {
            Note(symbol: "arrow.down.circle", text: "No downloads in progress in your Downloads folder.")
        }
        if let loginNote = model.loginNote {
            Note(symbol: "info.circle", text: loginNote)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Toggle("Open at login", isOn: Binding(
                get: { model.opensAtLogin },
                set: { model.setOpensAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(.espresso)
            .font(.system(size: 12))

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Text("Quit")
                    Text("⌘Q").foregroundStyle(.tertiary)
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
    }
}

// MARK: - Pieces

struct CupView: View {
    let active: Bool
    let animating: Bool
    let lidDot: Bool

    var body: some View {
        ZStack {
            Circle().fill(active ? Color.espresso : Color.primary.opacity(0.07))
            TimelineView(.animation(paused: !animating)) { timeline in
                Canvas { context, size in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: CupArt.cycleSeconds) / CupArt.cycleSeconds
                    let steam: CupArt.Steam = !active ? .hidden : animating ? .rising(phase: phase) : .still
                    let color = active ? Color.white : Color.secondary
                    let cgColor = color.resolve(in: context.environment).cgColor
                    context.withCGContext { cg in
                        CupArt.draw(in: cg, size: size.width, filled: false, steam: steam, lidDot: lidDot, color: cgColor)
                    }
                }
            }
            .frame(width: 28, height: 28)
        }
        .accessibilityHidden(true)
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

struct ChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.espresso : Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TileFace: View {
    let title: String
    let detail: String
    let symbol: String
    let isOn: Bool
    var opensMenu = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? Color.espresso : Color.primary.opacity(0.08))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        // In the corner rather than in the row, so the text keeps the same width as on the other tiles.
        .overlay(alignment: .topTrailing) {
            if opensMenu {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(7)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOn ? Color.espresso.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isOn ? Color.espresso.opacity(0.35) : Color.primary.opacity(0.08))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct Tile: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            TileFace(title: title, detail: detail, symbol: symbol, isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// macOS keeps only the text of a menu's label, so the style draws the whole tile face itself.
private struct TileMenuStyle: ButtonStyle {
    let face: TileFace

    func makeBody(configuration: Configuration) -> some View {
        face.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct Note<Accessory: View>: View {
    let symbol: String
    let text: String
    let accessory: Accessory

    init(symbol: String, text: String, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.text = text
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.espresso)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            accessory
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.espresso.opacity(0.08))
        )
    }
}

extension Note where Accessory == EmptyView {
    init(symbol: String, text: String) {
        self.init(symbol: symbol, text: text) { EmptyView() }
    }
}
