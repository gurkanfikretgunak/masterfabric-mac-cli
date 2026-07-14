import Foundation
import IOKit
import IOKit.ps

public enum BatteryService {
    public static func current() -> BatteryInfo {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else {
            return BatteryInfo(isPresent: false)
        }

        let percent = (desc[kIOPSCurrentCapacityKey] as? Int).map(Double.init)
        let isCharging = desc[kIOPSIsChargingKey] as? Bool
        let powerState = desc[kIOPSPowerSourceStateKey] as? String
        let isAC = powerState == kIOPSACPowerValue
        let cycles = desc["Cycle Count"] as? Int
            ?? readSMCInt("B0CT")
            ?? readIORegistryCycleCount()
        let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int
        let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int
        let remaining: Int?
        if isCharging == true {
            remaining = (timeToFull ?? -1) > 0 ? timeToFull : nil
        } else {
            remaining = (timeToEmpty ?? -1) > 0 ? timeToEmpty : nil
        }

        let design = readIORegistryInt("DesignCapacity")
        let full = readIORegistryInt("AppleRawMaxCapacity") ?? readIORegistryInt("MaxCapacity")
        var health: Double?
        if let design, let full, design > 0 {
            health = (Double(full) / Double(design) * 1000).rounded() / 10
        }

        let voltage = readIORegistryInt("Voltage").map(Double.init) // mV
        let amperage = readIORegistryInt("Amperage").map(Double.init) // mA
        var watts: Double?
        if let voltage, let amperage {
            watts = ((voltage / 1000) * (abs(amperage) / 1000) * 10).rounded() / 10
        }

        return BatteryInfo(
            percent: percent,
            isCharging: isCharging,
            isACPowered: isAC,
            cycleCount: cycles,
            healthPercent: health,
            watts: watts,
            timeRemainingMinutes: remaining,
            isPresent: true
        )
    }

    private static func readIORegistryCycleCount() -> Int? {
        readIORegistryInt("CycleCount")
    }

    private static func readIORegistryInt(_ key: String) -> Int? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let prop = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return nil }
        if let n = prop as? Int { return n }
        if let n = prop as? NSNumber { return n.intValue }
        return nil
    }

    private static func readSMCInt(_ key: String) -> Int? {
        guard let smc = try? SMCClient(), let v = smc.readNumber(key) else { return nil }
        return Int(v)
    }
}
