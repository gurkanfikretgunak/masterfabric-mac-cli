import Foundation

public enum SystemInfoService {
    public static func current() -> SystemInfo {
        let modelIdentifier = sysctlString("hw.model") ?? "Unknown"
        let chip = sysctlString("machdep.cpu.brand_string")
            ?? ProcessInfo.processInfo.processorCount.description
        let model = marketingName(for: modelIdentifier) ?? modelIdentifier
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let macOSVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let ramBytes = ProcessInfo.processInfo.physicalMemory
        let ramGB = Double(ramBytes) / 1_073_741_824.0
        let uptime = ProcessInfo.processInfo.systemUptime
        let cpuCount = ProcessInfo.processInfo.processorCount

        return SystemInfo(
            model: model,
            modelIdentifier: modelIdentifier,
            chip: chip,
            macOSVersion: macOSVersion,
            ramGB: (ramGB * 10).rounded() / 10,
            uptimeSeconds: uptime,
            cpuCount: cpuCount
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func marketingName(for identifier: String) -> String? {
        // Common Apple Silicon MacBook identifiers
        let map: [String: String] = [
            "Mac14,2": "MacBook Air (M2)",
            "Mac14,7": "MacBook Pro 13-inch (M2)",
            "Mac14,5": "MacBook Pro 14-inch (M2 Max)",
            "Mac14,6": "MacBook Pro 16-inch (M2 Max)",
            "Mac14,9": "MacBook Pro 14-inch (M2 Pro)",
            "Mac14,10": "MacBook Pro 16-inch (M2 Pro)",
            "Mac15,3": "MacBook Pro 14-inch (M3)",
            "Mac15,6": "MacBook Pro 14-inch (M3 Pro)",
            "Mac15,7": "MacBook Pro 16-inch (M3 Pro)",
            "Mac15,8": "MacBook Pro 14-inch (M3 Max)",
            "Mac15,9": "MacBook Pro 16-inch (M3 Max)",
            "Mac15,10": "MacBook Pro 14-inch (M3 Max)",
            "Mac15,11": "MacBook Pro 16-inch (M3 Max)",
            "Mac15,12": "MacBook Air 13-inch (M3)",
            "Mac15,13": "MacBook Air 15-inch (M3)",
            "Mac16,1": "MacBook Pro 14-inch (M4)",
            "Mac16,5": "MacBook Pro 14-inch (M4 Pro)",
            "Mac16,6": "MacBook Pro 16-inch (M4 Pro)",
            "Mac16,7": "MacBook Pro 14-inch (M4 Max)",
            "Mac16,8": "MacBook Pro 16-inch (M4 Max)",
            "Mac16,12": "MacBook Air 13-inch (M4)",
            "Mac16,13": "MacBook Air 15-inch (M4)",
            "MacBookAir10,1": "MacBook Air (M1)",
            "MacBookPro17,1": "MacBook Pro 13-inch (M1)",
            "MacBookPro18,1": "MacBook Pro 16-inch (M1 Pro)",
            "MacBookPro18,2": "MacBook Pro 16-inch (M1 Max)",
            "MacBookPro18,3": "MacBook Pro 14-inch (M1 Pro)",
            "MacBookPro18,4": "MacBook Pro 14-inch (M1 Max)",
        ]
        return map[identifier]
    }
}
