import Foundation

/// Turns `SleepDisabled` on and off. Changing it needs root: Espresso uses a passwordless sudo rule for
/// `pmset` when one exists, and otherwise the macOS administrator prompt.
@MainActor
final class ClosedLidMode {
    enum Failure: LocalizedError, Equatable {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "You cancelled the password prompt."
            case .failed(let message): message
            }
        }
    }

    nonisolated static let pmset = "/usr/bin/pmset"

    nonisolated static var defaultFlag: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Espresso", isDirectory: true)
            .appendingPathComponent("closed-lid.flag")
    }

    let flag: URL
    private var resetsWithSudo = false

    init(flag: URL) {
        self.flag = flag
    }

    func clearLeftoverFlag() {
        try? FileManager.default.removeItem(at: flag)
    }

    func enable() async throws {
        let flag = flag
        let pid = getpid()
        resetsWithSudo = try await Task.detached {
            try ClosedLidMode.performEnable(flag: flag, watchedPID: pid)
        }.value
    }

    /// The watchdog turns lid-close sleep back on within its poll interval once the flag is gone; with
    /// the sudo rule Espresso also does it right away.
    func disable() {
        try? FileManager.default.removeItem(at: flag)
        if resetsWithSudo {
            _ = try? Shell.run("/usr/bin/sudo", ["-n", Self.pmset, "-a", "disablesleep", "0"])
        }
    }

    func restoreSleep() async throws {
        try await Task.detached {
            if try Shell.run("/usr/bin/sudo", ["-n", ClosedLidMode.pmset, "-a", "disablesleep", "0"]).status == 0 {
                return
            }
            let script = AppleScript.doShellScript(
                "\(ClosedLidMode.pmset) -a disablesleep 0",
                prompt: "Espresso needs your password to let your Mac sleep when you close the lid again.",
                asAdministrator: true
            )
            try ClosedLidMode.runScript(script)
        }.value
    }

    /// True when the user's sudoers allows both `pmset -a disablesleep 1` and `0` without a password.
    nonisolated static func passwordlessRuleExists() -> Bool {
        ["1", "0"].allSatisfy { value in
            (try? Shell.run("/usr/bin/sudo", ["-n", "-l", pmset, "-a", "disablesleep", value]))?.status == 0
        }
    }

    /// Turns lid-close sleep off only while Espresso still runs and its flag exists, then starts the watchdog.
    /// The watchdog starts last so it always sees the final state: if Espresso died while the password prompt
    /// was open, the watchdog finds it gone and turns sleep straight back on.
    nonisolated static func enableCommand(flag: URL, watchedPID: pid_t, viaSudo: Bool) -> String {
        let pmsetCommand = viaSudo ? "/usr/bin/sudo -n \(pmset)" : pmset
        let watchdog = LidWatchdog(watchedPID: watchedPID, flag: flag, resetCommand: "\(pmsetCommand) -a disablesleep 0")
        return "/bin/kill -0 \(watchedPID) && [ -e \(Shell.quote(flag.path)) ] && "
            + "\(pmsetCommand) -a disablesleep 1 && { \(watchdog.launcher) }"
    }

    nonisolated static func enableScript(flag: URL, watchedPID: pid_t) -> String {
        AppleScript.doShellScript(
            enableCommand(flag: flag, watchedPID: watchedPID, viaSudo: false),
            prompt: "Espresso needs your password to keep your Mac awake with the lid closed.",
            asAdministrator: true
        )
    }

    /// Returns true when the passwordless sudo rule was used. Falls back to the password prompt when sudo
    /// refuses: `sudo -l` can list a command that still needs a password if the user has another
    /// NOPASSWD rule, and a refused `sudo -n` changes nothing.
    private nonisolated static func performEnable(flag: URL, watchedPID: pid_t) throws -> Bool {
        try FileManager.default.createDirectory(at: flag.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: flag)

        do {
            if passwordlessRuleExists(),
               try Shell.run("/bin/sh", ["-c", enableCommand(flag: flag, watchedPID: watchedPID, viaSudo: true)]).status == 0 {
                return true
            }
            try runScript(enableScript(flag: flag, watchedPID: watchedPID))
            return false
        } catch {
            try? FileManager.default.removeItem(at: flag)
            throw error
        }
    }

    private nonisolated static func runScript(_ script: String) throws {
        let result = try Shell.run("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else {
            if result.output.contains("(-128)") {
                throw Failure.cancelled
            }
            throw Failure.failed(message(from: result.output))
        }
    }

    /// osascript prefixes errors with "0:123: execution error: "; keep only the readable part.
    private nonisolated static func message(from output: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "execution error: ") {
            text = String(text[range.upperBound...])
        }
        return text.isEmpty ? "Couldn't change the sleep setting." : text
    }
}
