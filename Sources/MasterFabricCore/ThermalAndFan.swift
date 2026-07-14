import Foundation

public enum ThermalService {
    /// Known SMC temperature keys (Apple Silicon + Intel best-effort).
    private static let cpuKeys = [
        "Tp09", "Tp0T", "Tp0G", "Tp1H", "Tp05", "Tp01", "Tp00",
        "TC0P", "TC0E", "TC0F", "TCAD", "TC0H", "TC0c", "TC0C",
    ]
    private static let gpuKeys = [
        "Tg0D", "Tg0L", "Tg0P", "Tg05", "Tg0H", "Tg1H",
        "TG0P", "TGDD", "TG0D", "TCGC", "Tg0F",
    ]

    public static func read() -> TemperatureReading {
        var sensors: [String: Double] = [:]
        var cpu: Double?
        var gpu: Double?

        let hid = HIDThermalReader.readSensors()
        for (name, value) in hid {
            sensors[name] = round1(value)
        }

        if let smc = try? SMCClient() {
            for key in cpuKeys {
                if let v = smc.readNumber(key), v > 0, v < 120 {
                    sensors["SMC:\(key)"] = round1(v)
                    if cpu == nil { cpu = round1(v) }
                }
            }
            for key in gpuKeys {
                if let v = smc.readNumber(key), v > 0, v < 120 {
                    sensors["SMC:\(key)"] = round1(v)
                    if gpu == nil { gpu = round1(v) }
                }
            }
        }

        if cpu == nil {
            cpu = pick(from: sensors, matching: ["cpu", "soc", "p-core", "e-core", "ane", "mtr"])
        }
        if gpu == nil {
            gpu = pick(from: sensors, matching: ["gpu", "graphics"])
        }

        // Prefer DIE / package style names from HID product strings used on AS
        if cpu == nil {
            cpu = pick(from: sensors, matching: ["thermal", "die", "package", "avg"])
        }
        if cpu == nil, let maxSensor = sensors.values.filter({ $0 > 20 && $0 < 110 }).max() {
            cpu = maxSensor
        }

        return TemperatureReading(cpuCelsius: cpu, gpuCelsius: gpu, sensors: sensors)
    }

    private static func pick(from sensors: [String: Double], matching needles: [String]) -> Double? {
        let matches = sensors.filter { key, value in
            guard value > 15, value < 120 else { return false }
            let lower = key.lowercased()
            return needles.contains { lower.contains($0) }
        }
        return matches.values.max().map(round1)
    }

    private static func round1(_ v: Double) -> Double {
        (v * 10).rounded() / 10
    }
}

public enum FanService {
    public static func read() -> [FanReading] {
        guard let smc = try? SMCClient() else { return [] }

        let count: Int
        if let n = smc.readUInt8("FNum") {
            count = Int(n)
        } else if let n = smc.readNumber("FNum") {
            count = Int(n)
        } else {
            count = 0
        }
        guard count > 0 else { return [] }

        var fans: [FanReading] = []
        for i in 0..<min(count, 10) {
            let rpm = smc.readNumber("F\(i)Ac")
            let minRPM = smc.readNumber("F\(i)Mn")
            let maxRPM = smc.readNumber("F\(i)Mx")
            fans.append(
                FanReading(
                    name: "Fan \(i)",
                    rpm: rpm.map { $0.rounded() },
                    minRPM: minRPM,
                    maxRPM: maxRPM
                )
            )
        }
        return fans
    }
}

public enum StatusService {
    public static func current() -> SystemStatus {
        SystemStatus(
            temperature: ThermalService.read(),
            fans: FanService.read()
        )
    }
}
