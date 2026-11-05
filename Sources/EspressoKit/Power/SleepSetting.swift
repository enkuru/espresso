import Foundation

/// The system-wide `SleepDisabled` power setting. It is the only switch that keeps a closed MacBook
/// awake without an external display; power assertions do not.
enum SleepSetting {
    static func isDisabled() -> Bool {
        guard let result = try? Shell.run("/usr/bin/pmset", ["-g"]) else { return false }
        return isDisabled(pmsetOutput: result.output)
    }

    static func isDisabled(pmsetOutput: String) -> Bool {
        pmsetOutput.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count == 2 && fields[0] == "SleepDisabled" && fields[1] == "1"
        }
    }
}
