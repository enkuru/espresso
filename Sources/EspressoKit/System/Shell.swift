import Foundation

struct ShellResult {
    let status: Int32
    let output: String
}

enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

enum AppleScript {
    static func doShellScript(_ command: String, prompt: String? = nil, asAdministrator: Bool) -> String {
        var script = "do shell script \(literal(command))"
        if let prompt {
            script += " with prompt \(literal(prompt))"
        }
        if asAdministrator {
            script += " with administrator privileges"
        }
        return script
    }

    static func literal(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
