import Foundation
import Testing
@testable import EspressoKit

struct SleepSettingTests {
    @Test func readsSleepDisabledOn() {
        let output = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         standby              1
        """
        #expect(SleepSetting.isDisabled(pmsetOutput: output))
    }

    @Test func readsSleepDisabledOff() {
        #expect(!SleepSetting.isDisabled(pmsetOutput: " SleepDisabled\t\t0\n sleep 1\n"))
    }

    @Test func treatsMissingSettingAsOff() {
        #expect(!SleepSetting.isDisabled(pmsetOutput: "Currently in use:\n sleep 1\n displaysleep 10\n"))
    }
}

struct DownloadsTests {
    @Test(arguments: ["movie.mp4.crdownload", "a.download", "big.iso.part", "x.partial", "y.opdownload", "Z.CRDOWNLOAD"])
    func recognisesPartialFiles(name: String) {
        #expect(Downloads.isInProgress(name))
    }

    @Test(arguments: ["movie.mp4", "partial.txt", "notes.parts", "download"])
    func ignoresFinishedFiles(name: String) {
        #expect(!Downloads.isInProgress(name))
    }

    @Test func countsPartialFilesAndSafariBundles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        for name in ["a.zip.crdownload", "b.dmg", "c.part"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("d.pkg.download"), withIntermediateDirectories: true)

        #expect(Downloads.inProgressCount(in: folder) == 3)
    }
}

struct CountdownTests {
    @Test func shortForm() {
        #expect(Countdown.short(0) == "0s")
        #expect(Countdown.short(45) == "45s")
        #expect(Countdown.short(60) == "1m")
        #expect(Countdown.short(61) == "2m")
        #expect(Countdown.short(1_500) == "25m")
        #expect(Countdown.short(3_600) == "1h")
        #expect(Countdown.short(6_130) == "1h 43m")
    }

    @Test func menuBarForm() {
        #expect(Countdown.menuBar(6_130) == "1:43")
        #expect(Countdown.menuBar(1_500) == "0:25")
        #expect(Countdown.menuBar(1) == "0:01")
        #expect(Countdown.menuBar(28_800) == "8:00")
    }
}

struct BatteryTests {
    @Test func lowOnlyOnBattery() {
        #expect(BatteryStatus(percent: 20, onBattery: true).isLow(threshold: 20))
        #expect(!BatteryStatus(percent: 21, onBattery: true).isLow(threshold: 20))
        #expect(!BatteryStatus(percent: 5, onBattery: false).isLow(threshold: 20))
    }
}

struct CupArtTests {
    @Test func steamFadesInThenOut() {
        let start = CupArt.wispOffset(.rising(phase: 0), index: 0)
        let peak = CupArt.wispOffset(.rising(phase: 0.35), index: 0)
        let end = CupArt.wispOffset(.rising(phase: 0.999), index: 0)
        #expect(start.alpha == 0 && start.rise == 2)
        #expect(abs(peak.alpha - 1) < 0.001)
        #expect(end.alpha < 0.01 && end.rise < -2.9)
    }

    @Test func wispsAreAThirdOfACycleApart() {
        let first = CupArt.wispOffset(.rising(phase: 0), index: 0)
        let second = CupArt.wispOffset(.rising(phase: 1.0 / 3), index: 1)
        #expect(first == second)
    }
}
