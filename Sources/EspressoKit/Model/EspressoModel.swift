import AppKit
import IOKit.pwr_mgt
import Observation
import ServiceManagement

@MainActor
@Observable
final class EspressoModel {
    enum ClosedLidState: Equatable {
        case off
        case waitingForPassword
        case on
        case failed(String)
    }

    struct RunningApp: Identifiable {
        let pid: pid_t
        let name: String
        let icon: NSImage
        var id: pid_t { pid }
    }

    var session: Session?
    var endReason: String?
    var now = Date()
    var closedLidState = ClosedLidState.off
    var downloadsLeft = 0
    var noDownloadsFound = false
    var runningApps: [RunningApp] = []
    var sleepDisabledOutsideSession = false
    var restoreError: String?
    var hasPasswordlessRule = false
    var opensAtLogin = false
    var loginNote: String?

    var keepScreenOn: Bool {
        didSet { defaults.set(keepScreenOn, forKey: Key.keepScreenOn); applyHolds() }
    }
    var closedLid: Bool {
        didSet { defaults.set(closedLid, forKey: Key.closedLid); applyHolds() }
    }
    var stopOnLowBattery: Bool {
        didSet { defaults.set(stopOnLowBattery, forKey: Key.stopOnLowBattery) }
    }
    /// The battery level, in percent, at which a session stops while the Mac runs on battery.
    var lowBatteryPercent: Int {
        didSet { defaults.set(lowBatteryPercent, forKey: Key.lowBatteryPercent) }
    }
    var animateIcon: Bool {
        didSet { defaults.set(animateIcon, forKey: Key.animateIcon) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let lid: ClosedLidMode
    @ObservationIgnored private var systemHold: PowerAssertion?
    @ObservationIgnored private var displayHold: PowerAssertion?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var quitObserver: NSObjectProtocol?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var emptyDownloadChecks = 0

    private enum Key {
        static let keepScreenOn = "keepScreenOn"
        static let closedLid = "closedLid"
        static let stopOnLowBattery = "stopOnLowBattery"
        static let lowBatteryPercent = "lowBatteryPercent"
        static let animateIcon = "animateIcon"
    }

    init(defaults: UserDefaults = .standard, lidFlag: URL = ClosedLidMode.defaultFlag) {
        self.defaults = defaults
        lid = ClosedLidMode(flag: lidFlag)
        keepScreenOn = defaults.object(forKey: Key.keepScreenOn) as? Bool ?? true
        closedLid = defaults.object(forKey: Key.closedLid) as? Bool ?? false
        stopOnLowBattery = defaults.object(forKey: Key.stopOnLowBattery) as? Bool ?? true
        lowBatteryPercent = min(max(defaults.object(forKey: Key.lowBatteryPercent) as? Int ?? 20, 1), 99)
        animateIcon = defaults.object(forKey: Key.animateIcon) as? Bool ?? true
    }

    // MARK: Sessions

    func start(_ length: SessionLength) {
        noDownloadsFound = false
        switch length {
        case .untilAppQuits(let pid, _):
            guard NSRunningApplication(processIdentifier: pid) != nil else { return }
        case .untilDownloadsFinish:
            downloadsLeft = Downloads.inProgressCount()
            guard downloadsLeft > 0 else {
                noDownloadsFound = true
                return
            }
        case .indefinitely, .timed:
            break
        }

        stopTracking()
        session = Session(length: length, startedAt: Date())
        endReason = nil
        now = Date()
        ticks = 0
        emptyDownloadChecks = 0
        if case .untilAppQuits(let pid, let name) = length {
            watchQuit(of: pid, name: name)
        }
        startTicker()
        applyHolds()
    }

    func toggle() {
        if session == nil {
            start(.indefinitely)
        } else {
            stop(reason: nil)
        }
    }

    func stop(reason: String?) {
        guard session != nil else { return }
        stopTracking()
        session = nil
        endReason = reason
        downloadsLeft = 0
        applyHolds()
    }

    private func stopTracking() {
        ticker?.invalidate()
        ticker = nil
        if let quitObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(quitObserver)
        }
        quitObserver = nil
    }

    private func startTicker() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let session else { return }
        now = Date()
        ticks += 1

        if let endsAt = session.endsAt, now >= endsAt {
            stop(reason: "timer ended")
            return
        }
        if session.length == .untilDownloadsFinish, ticks % 3 == 0 {
            checkDownloads()
        }
        if self.session != nil, stopOnLowBattery, ticks % 30 == 1,
           let battery = BatteryStatus.current(), battery.isLow(threshold: lowBatteryPercent) {
            stop(reason: "battery at \(battery.percent)%")
        }
    }

    /// Two empty checks in a row, because browsers briefly have no partial file between a download's parts.
    private func checkDownloads() {
        downloadsLeft = Downloads.inProgressCount()
        emptyDownloadChecks = downloadsLeft == 0 ? emptyDownloadChecks + 1 : 0
        if emptyDownloadChecks >= 2 {
            stop(reason: "downloads finished")
        }
    }

    private func watchQuit(of pid: pid_t, name: String) {
        quitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier == pid else { return }
            MainActor.assumeIsolated { self?.stop(reason: "\(name) quit") }
        }
    }

    // MARK: Holds

    private func applyHolds() {
        let active = session != nil
        if active, systemHold == nil {
            systemHold = PowerAssertion(kIOPMAssertionTypePreventUserIdleSystemSleep, reason: "Espresso is keeping your Mac awake")
        } else if !active {
            systemHold = nil
        }

        let holdsScreen = active && keepScreenOn
        if holdsScreen, displayHold == nil {
            displayHold = PowerAssertion(kIOPMAssertionTypePreventUserIdleDisplaySleep, reason: "Espresso is keeping your screen on")
        } else if !holdsScreen {
            displayHold = nil
        }

        syncClosedLid()
    }

    private func syncClosedLid() {
        let wanted = session != nil && closedLid
        switch (closedLidState, wanted) {
        case (.off, true):
            enableClosedLid()
        case (.on, false):
            lid.disable()
            closedLidState = .off
        case (.failed, false):
            closedLidState = .off
        default:
            break
        }
    }

    private func enableClosedLid() {
        closedLidState = .waitingForPassword
        Task {
            do {
                try await lid.enable()
                closedLidState = .on
                sleepDisabledOutsideSession = false
            } catch ClosedLidMode.Failure.cancelled {
                closedLidState = .off
                closedLid = false
            } catch {
                closedLidState = .failed(error.localizedDescription)
            }
            // The session or the toggle may have changed while the prompt was open.
            syncClosedLid()
        }
    }

    // MARK: Panel state

    var statusLine: String {
        guard let session else {
            return endReason.map { "Off · \($0)" } ?? "Off · Mac sleeps normally"
        }
        switch session.length {
        case .indefinitely:
            return "Awake · indefinitely"
        case .timed:
            return "Awake · \(Countdown.short(secondsLeft ?? 0)) left"
        case .untilAppQuits(_, let name):
            return "Awake · until \(name) quits"
        case .untilDownloadsFinish:
            switch downloadsLeft {
            case 0: return "Awake · finishing downloads"
            case 1: return "Awake · until 1 download finishes"
            default: return "Awake · until \(downloadsLeft) downloads finish"
            }
        }
    }

    var holdingLine: String? {
        guard session != nil else { return nil }
        var parts = ["system"]
        if keepScreenOn {
            parts.append("screen")
        }
        switch closedLidState {
        case .on: parts.append("lid closed")
        case .waitingForPassword: parts.append("lid closed (waiting for password)")
        case .off, .failed: break
        }
        return "Holding: " + parts.joined(separator: ", ")
    }

    var secondsLeft: Int? {
        guard let endsAt = session?.endsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }

    /// Share of a timed session still left, from 1 down to 0.
    var progress: Double? {
        guard let session, case .timed(let total) = session.length, total > 0, let secondsLeft else { return nil }
        return Double(secondsLeft) / Double(total)
    }

    var menuBarCountdown: String? {
        secondsLeft.map(Countdown.menuBar)
    }

    // MARK: System checks and settings

    func prepareAfterLaunch() {
        lid.clearLeftoverFlag()
        refresh()
    }

    /// Runs when the panel opens.
    func refresh() {
        let me = ProcessInfo.processInfo.processIdentifier
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
            .compactMap { app in
                guard let name = app.localizedName else { return nil }
                let icon = (app.icon?.copy() as? NSImage) ?? NSWorkspace.shared.icon(for: .application)
                icon.size = NSSize(width: 16, height: 16)
                return RunningApp(pid: app.processIdentifier, name: name, icon: icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        updateLoginState()

        Task {
            let (disabled, rule) = await Task.detached {
                (SleepSetting.isDisabled(), ClosedLidMode.passwordlessRuleExists())
            }.value
            sleepDisabledOutsideSession = disabled && closedLidState == .off
            hasPasswordlessRule = rule
        }
    }

    func restoreSleep() {
        restoreError = nil
        Task {
            do {
                try await lid.restoreSleep()
                sleepDisabledOutsideSession = false
            } catch ClosedLidMode.Failure.cancelled {
                return
            } catch {
                restoreError = error.localizedDescription
            }
        }
    }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginNote = nil
        } catch {
            loginNote = "Couldn't change Open at login: \(error.localizedDescription)"
        }
        updateLoginState()
    }

    private func updateLoginState() {
        let status = SMAppService.mainApp.status
        opensAtLogin = status == .enabled
        if status == .requiresApproval {
            loginNote = "Allow Espresso in System Settings › General › Login Items."
        }
    }
}
