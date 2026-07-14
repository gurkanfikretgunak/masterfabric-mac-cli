import Foundation

public struct SystemInfo: Sendable, Codable, Equatable {
    public var model: String
    public var modelIdentifier: String
    public var chip: String
    public var macOSVersion: String
    public var ramGB: Double
    public var uptimeSeconds: TimeInterval
    public var cpuCount: Int

    public init(
        model: String,
        modelIdentifier: String,
        chip: String,
        macOSVersion: String,
        ramGB: Double,
        uptimeSeconds: TimeInterval,
        cpuCount: Int
    ) {
        self.model = model
        self.modelIdentifier = modelIdentifier
        self.chip = chip
        self.macOSVersion = macOSVersion
        self.ramGB = ramGB
        self.uptimeSeconds = uptimeSeconds
        self.cpuCount = cpuCount
    }

    public var uptimeFormatted: String {
        let total = Int(uptimeSeconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

public struct FanReading: Sendable, Codable, Equatable {
    public var name: String
    public var rpm: Double?
    public var minRPM: Double?
    public var maxRPM: Double?

    public init(name: String, rpm: Double?, minRPM: Double? = nil, maxRPM: Double? = nil) {
        self.name = name
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

public struct TemperatureReading: Sendable, Codable, Equatable {
    public var cpuCelsius: Double?
    public var gpuCelsius: Double?
    public var sensors: [String: Double]

    public init(cpuCelsius: Double?, gpuCelsius: Double?, sensors: [String: Double] = [:]) {
        self.cpuCelsius = cpuCelsius
        self.gpuCelsius = gpuCelsius
        self.sensors = sensors
    }
}

public struct SystemStatus: Sendable, Codable, Equatable {
    public var temperature: TemperatureReading
    public var fans: [FanReading]
    public var timestamp: Date

    public init(temperature: TemperatureReading, fans: [FanReading], timestamp: Date = Date()) {
        self.temperature = temperature
        self.fans = fans
        self.timestamp = timestamp
    }
}
