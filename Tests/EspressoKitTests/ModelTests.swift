import Foundation
import Testing
@testable import EspressoKit

/// The lid toggle stays off in these tests, so nothing asks for a password.
@MainActor
@Suite(.serialized)
struct ModelTests {
    private let suiteName = "espresso-tests-\(UUID().uuidString)"
    private let model: EspressoModel

    init() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let flag = FileManager.default.temporaryDirectory.appendingPathComponent("\(suiteName).flag")
        model = EspressoModel(defaults: defaults, lidFlag: flag)
    }

    @Test func startsOffWithDefaults() {
        #expect(model.session == nil)
        #expect(model.statusLine == "Off · Mac sleeps normally")
        #expect(model.keepScreenOn && !model.closedLid && model.stopOnLowBattery && model.animateIcon)
        #expect(model.lowBatteryPercent == 20)
        #expect(model.holdingLine == nil)
    }

    @Test func batteryLevelOutsideOneTo99IsClamped() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(500, forKey: "lowBatteryPercent")
        #expect(EspressoModel(defaults: defaults).lowBatteryPercent == 99)
        defaults.set(0, forKey: "lowBatteryPercent")
        #expect(EspressoModel(defaults: defaults).lowBatteryPercent == 1)
    }

    @Test func timedSessionCountsDown() {
        model.start(.timed(seconds: 3_600))
        defer { model.stop(reason: nil) }

        #expect(model.statusLine == "Awake · 1h left")
        #expect(model.menuBarCountdown == "1:00")
        #expect(model.progress == 1)
        #expect(model.holdingLine == "Holding: system, screen")

        model.now = Date().addingTimeInterval(1_200)
        #expect(model.statusLine == "Awake · 40m left")
        #expect(model.menuBarCountdown == "0:40")
    }

    @Test func screenOffLeavesOnlyTheSystemHold() {
        model.keepScreenOn = false
        model.start(.indefinitely)
        defer { model.stop(reason: nil) }

        #expect(model.statusLine == "Awake · indefinitely")
        #expect(model.holdingLine == "Holding: system")
        #expect(model.menuBarCountdown == nil)
    }

    @Test func stopShowsTheReason() {
        model.start(.indefinitely)
        model.stop(reason: "timer ended")
        #expect(model.session == nil)
        #expect(model.statusLine == "Off · timer ended")
    }

    @Test func toggleStartsIndefinitelyAndStops() {
        model.toggle()
        #expect(model.session?.length == .indefinitely)
        model.toggle()
        #expect(model.session == nil)
    }

    @Test func settingsPersist() {
        model.animateIcon = false
        model.stopOnLowBattery = false
        model.lowBatteryPercent = 35
        let again = EspressoModel(defaults: UserDefaults(suiteName: suiteName)!)
        #expect(!again.animateIcon && !again.stopOnLowBattery)
        #expect(again.lowBatteryPercent == 35)
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
    }

    /// Checks the real IOKit holds through the same tool macOS users would use. Only this test process's
    /// lines count, because an installed Espresso may hold the same names at the same time.
    @Test func holdsShowUpInPmsetOnlyDuringASession() throws {
        func ownHolds() throws -> String {
            try Shell.run("/usr/bin/pmset", ["-g", "assertions"]).output
                .split(separator: "\n")
                .filter { $0.contains("pid \(getpid())(") }
                .joined(separator: "\n")
        }

        model.start(.indefinitely)
        let during = try ownHolds()
        model.keepScreenOn = false
        let screenOff = try ownHolds()
        model.stop(reason: nil)
        let after = try ownHolds()

        #expect(during.contains("Espresso is keeping your Mac awake"))
        #expect(during.contains("Espresso is keeping your screen on"))
        #expect(screenOff.contains("Espresso is keeping your Mac awake"))
        #expect(!screenOff.contains("Espresso is keeping your screen on"))
        #expect(!after.contains("Espresso is keeping"))
    }

    @Test func refusesAnAppThatIsNotRunning() {
        model.start(.untilAppQuits(pid: 999_999, name: "Ghost"))
        #expect(model.session == nil)
    }
}
