import Foundation

// MARK: - Phase 2 metrics

public struct BatteryInfo: Sendable, Codable, Equatable {
    public var percent: Double?
    public var isCharging: Bool?
    public var isACPowered: Bool?
    public var cycleCount: Int?
    public var healthPercent: Double?
    public var watts: Double?
    public var timeRemainingMinutes: Int?
    public var isPresent: Bool

    public init(
        percent: Double? = nil,
        isCharging: Bool? = nil,
        isACPowered: Bool? = nil,
        cycleCount: Int? = nil,
        healthPercent: Double? = nil,
        watts: Double? = nil,
        timeRemainingMinutes: Int? = nil,
        isPresent: Bool = true
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.isACPowered = isACPowered
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.watts = watts
        self.timeRemainingMinutes = timeRemainingMinutes
        self.isPresent = isPresent
    }
}

public struct MemoryInfo: Sendable, Codable, Equatable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var freeBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var swapUsedBytes: UInt64
    public var pressure: String

    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        freeBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        swapUsedBytes: UInt64,
        pressure: String
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
    }
}

public struct DiskInfo: Sendable, Codable, Equatable {
    public var path: String
    public var totalBytes: UInt64
    public var freeBytes: UInt64
    public var usedBytes: UInt64

    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }

    public init(path: String, totalBytes: UInt64, freeBytes: UInt64, usedBytes: UInt64) {
        self.path = path
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.usedBytes = usedBytes
    }
}

public struct NetworkInterfaceStats: Sendable, Codable, Equatable {
    public var name: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var bytesInPerSec: Double?
    public var bytesOutPerSec: Double?

    public init(
        name: String,
        bytesIn: UInt64,
        bytesOut: UInt64,
        bytesInPerSec: Double? = nil,
        bytesOutPerSec: Double? = nil
    ) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.bytesInPerSec = bytesInPerSec
        self.bytesOutPerSec = bytesOutPerSec
    }
}

public struct NetworkInfo: Sendable, Codable, Equatable {
    public var interfaces: [NetworkInterfaceStats]

    public init(interfaces: [NetworkInterfaceStats]) {
        self.interfaces = interfaces
    }
}

public struct CPULoadInfo: Sendable, Codable, Equatable {
    public var overallPercent: Double
    public var perCorePercent: [Double]
    public var userPercent: Double
    public var systemPercent: Double
    public var idlePercent: Double

    public init(
        overallPercent: Double,
        perCorePercent: [Double],
        userPercent: Double,
        systemPercent: Double,
        idlePercent: Double
    ) {
        self.overallPercent = overallPercent
        self.perCorePercent = perCorePercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
    }
}

// MARK: - Phase 4

public struct PowerInfo: Sendable, Codable, Equatable {
    public var thermalState: String
    public var lowPowerMode: Bool

    public init(thermalState: String, lowPowerMode: Bool) {
        self.thermalState = thermalState
        self.lowPowerMode = lowPowerMode
    }
}

public struct ProcessCPUInfo: Sendable, Codable, Equatable {
    public var pid: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64

    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}

public struct HistorySample: Sendable, Codable, Equatable {
    public var timestamp: Date
    public var cpuCelsius: Double?
    public var gpuCelsius: Double?
    public var fanRPM: Double?
    public var cpuLoadPercent: Double?
    public var batteryPercent: Double?

    public init(
        timestamp: Date = Date(),
        cpuCelsius: Double? = nil,
        gpuCelsius: Double? = nil,
        fanRPM: Double? = nil,
        cpuLoadPercent: Double? = nil,
        batteryPercent: Double? = nil
    ) {
        self.timestamp = timestamp
        self.cpuCelsius = cpuCelsius
        self.gpuCelsius = gpuCelsius
        self.fanRPM = fanRPM
        self.cpuLoadPercent = cpuLoadPercent
        self.batteryPercent = batteryPercent
    }
}

public struct HistorySnapshot: Sendable, Codable, Equatable {
    public var samples: [HistorySample]
    public var cpuSparkline: String
    public var loadSparkline: String

    public init(samples: [HistorySample], cpuSparkline: String, loadSparkline: String) {
        self.samples = samples
        self.cpuSparkline = cpuSparkline
        self.loadSparkline = loadSparkline
    }
}

// MARK: - Phase 3 config

public struct AlertConfig: Sendable, Codable, Equatable {
    public var cpuTempCelsius: Double
    public var fanNearMaxPercent: Double
    public var memoryPressureNotify: Bool
    public var enabled: Bool

    public static let `default` = AlertConfig(
        cpuTempCelsius: 90,
        fanNearMaxPercent: 95,
        memoryPressureNotify: true,
        enabled: true
    )

    public init(
        cpuTempCelsius: Double,
        fanNearMaxPercent: Double,
        memoryPressureNotify: Bool,
        enabled: Bool
    ) {
        self.cpuTempCelsius = cpuTempCelsius
        self.fanNearMaxPercent = fanNearMaxPercent
        self.memoryPressureNotify = memoryPressureNotify
        self.enabled = enabled
    }
}

public struct AppConfig: Sendable, Codable, Equatable {
    public var language: String
    public var launchAtLogin: Bool
    public var pollIntervalSeconds: Double
    public var alerts: AlertConfig

    public static let `default` = AppConfig(
        language: "en",
        launchAtLogin: false,
        pollIntervalSeconds: 2.0,
        alerts: .default
    )

    public init(
        language: String,
        launchAtLogin: Bool,
        pollIntervalSeconds: Double,
        alerts: AlertConfig
    ) {
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.pollIntervalSeconds = pollIntervalSeconds
        self.alerts = alerts
    }
}
