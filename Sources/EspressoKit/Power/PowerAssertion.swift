import IOKit.pwr_mgt

/// Holds one IOKit power assertion while the instance lives. macOS also drops it if Espresso dies,
/// so these holds can never outlive the app.
final class PowerAssertion {
    private var id = IOPMAssertionID(0)

    init?(_ type: String, reason: String) {
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)
        guard IOPMAssertionCreateWithName(type as CFString, level, reason as CFString, &id) == kIOReturnSuccess else {
            return nil
        }
    }

    deinit {
        IOPMAssertionRelease(id)
    }
}
