import Foundation

/// The fail-safe for lid-closed mode: a shell loop that turns lid-close sleep back on as soon as
/// Espresso exits for any reason or removes the flag file.
struct LidWatchdog {
    let watchedPID: pid_t
    let flag: URL
    let resetCommand: String
    var pollSeconds = 2.0

    /// Starts the loop and returns at once. `set -m` gives the loop its own process group, because launchd
    /// kills the app's whole group when the app dies, and the loop must outlive the app.
    var launcher: String {
        let loop = "while /bin/kill -0 \(watchedPID) 2>/dev/null && [ -e \(Shell.quote(flag.path)) ]; "
            + "do /bin/sleep \(pollSeconds); done; \(resetCommand)"
        return "set -m; /bin/sh -c \(Shell.quote(loop)) </dev/null >/dev/null 2>&1 &"
    }
}
