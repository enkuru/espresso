import Foundation
import Testing
@testable import EspressoKit

/// Runs the real watchdog shell loop, with `touch` standing in for `pmset` so no root is needed.
@Suite(.serialized)
struct LidWatchdogTests {
    private let folder: URL
    private let flag: URL
    private let marker: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("espresso-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        flag = folder.appendingPathComponent("closed-lid.flag")
        marker = folder.appendingPathComponent("reset-ran")
        try Data().write(to: flag)
    }

    private func launch(watching pid: pid_t) throws {
        let watchdog = LidWatchdog(
            watchedPID: pid,
            flag: flag,
            resetCommand: "/usr/bin/touch \(Shell.quote(marker.path))",
            pollSeconds: 0.2
        )
        let result = try Shell.run("/bin/sh", ["-c", watchdog.launcher])
        #expect(result.status == 0)
    }

    private func resetRan(within seconds: Double) async throws -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: marker.path) { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return FileManager.default.fileExists(atPath: marker.path)
    }

    @Test func resetsWhenTheFlagIsRemoved() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try launch(watching: getpid())

        #expect(try await !resetRan(within: 0.8))
        try FileManager.default.removeItem(at: flag)
        #expect(try await resetRan(within: 3))
    }

    @Test func resetsWhenTheWatchedProcessExits() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        try launch(watching: sleeper.processIdentifier)

        #expect(try await !resetRan(within: 0.8))
        sleeper.terminate()
        sleeper.waitUntilExit()
        #expect(try await resetRan(within: 3))
        try? FileManager.default.removeItem(at: flag)
    }

    /// launchd kills the app's process group when the app dies, so the loop must live in a group of its own.
    @Test func runsInItsOwnProcessGroup() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try launch(watching: getpid())

        let found = try Shell.run("/usr/bin/pgrep", ["-f", flag.path])
        let pid = try #require(found.output.split(separator: "\n").first.map(String.init))
        let group = try Shell.run("/bin/ps", ["-o", "pgid=", "-p", pid]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!group.isEmpty)
        #expect(group != String(getpgrp()))

        try FileManager.default.removeItem(at: flag)
        #expect(try await resetRan(within: 3))
    }

    /// If Espresso died while the password prompt was open, the command must stop before pmset runs.
    /// PIDs on macOS stay below 100000, so 999999 is never alive and pmset is never reached.
    @Test func enableCommandDoesNothingWhenTheAppIsGone() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let command = ClosedLidMode.enableCommand(flag: flag, watchedPID: 999_999, viaSudo: false)

        let syntax = try Shell.run("/bin/sh", ["-n", "-c", command])
        #expect(syntax.status == 0, "shell syntax: \(syntax.output)")
        #expect(command.contains("/usr/bin/pmset -a disablesleep 1 && { set -m;"))

        let run = try Shell.run("/bin/sh", ["-c", command])
        #expect(run.status != 0)
        #expect(try Shell.run("/usr/bin/pgrep", ["-f", flag.path]).output.isEmpty)
    }
}

struct AppleScriptTests {
    @Test func doShellScriptKeepsQuotesAndBackslashes() throws {
        let tricky = #"a "quoted" \ back'slash"#
        let script = AppleScript.doShellScript("printf %s \(Shell.quote(tricky))", asAdministrator: false)
        let result = try Shell.run("/usr/bin/osascript", ["-e", script])
        #expect(result.status == 0)
        #expect(result.output.trimmingCharacters(in: .newlines) == tricky)
    }

    @Test func enableScriptCompiles() throws {
        let flag = URL(fileURLWithPath: "/tmp/it's a \"flag\"/closed-lid.flag")
        let script = ClosedLidMode.enableScript(flag: flag, watchedPID: 123)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).scpt")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try Shell.run("/usr/bin/osacompile", ["-o", output.path, "-e", script])
        #expect(result.status == 0, "osacompile: \(result.output)")
        #expect(script.hasSuffix("with administrator privileges"))
    }
}
