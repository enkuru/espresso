import IOKit.ps

struct BatteryStatus: Equatable {
    let percent: Int
    let onBattery: Bool

    /// Nil on a Mac without an internal battery.
    static func current() -> BatteryStatus? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0
            else { continue }

            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return BatteryStatus(percent: current * 100 / maximum, onBattery: onBattery)
        }
        return nil
    }

    func isLow(threshold: Int) -> Bool {
        onBattery && percent <= threshold
    }
}
