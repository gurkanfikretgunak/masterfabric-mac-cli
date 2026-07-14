import Darwin
import Foundation

public enum NetworkService {
    private static var previous: [String: (inBytes: UInt64, outBytes: UInt64, at: Date)] = [:]
    private static let lock = NSLock()

    public static func current() -> NetworkInfo {
        var interfaces: [NetworkInterfaceStats] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return NetworkInfo(interfaces: [])
        }
        defer { freeifaddrs(ifaddr) }

        var seen = Set<String>()
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        let now = Date()

        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("awdl") || name.hasPrefix("bridge") || name.hasPrefix("pdp_ip") || name.hasPrefix("utun") else {
                continue
            }
            guard current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard !seen.contains(name) else { continue }
            seen.insert(name)

            let data = unsafeBitCast(current.pointee.ifa_data, to: UnsafeMutablePointer<if_data>?.self)
            guard let data else { continue }
            let bytesIn = UInt64(data.pointee.ifi_ibytes)
            let bytesOut = UInt64(data.pointee.ifi_obytes)

            var inRate: Double?
            var outRate: Double?
            lock.lock()
            if let prev = previous[name] {
                let dt = now.timeIntervalSince(prev.at)
                if dt > 0.2 {
                    inRate = Double(bytesIn &- prev.inBytes) / dt
                    outRate = Double(bytesOut &- prev.outBytes) / dt
                }
            }
            previous[name] = (bytesIn, bytesOut, now)
            lock.unlock()

            interfaces.append(
                NetworkInterfaceStats(
                    name: name,
                    bytesIn: bytesIn,
                    bytesOut: bytesOut,
                    bytesInPerSec: inRate,
                    bytesOutPerSec: outRate
                )
            )
        }

        interfaces.sort { $0.name < $1.name }
        return NetworkInfo(interfaces: interfaces)
    }
}

public enum CPULoadService {
    private static var previous: processor_info_array_t?
    private static var previousCount: mach_msg_type_number_t = 0
    private static var previousCoreCount: natural_t = 0
    private static let lock = NSLock()

    public static func current() -> CPULoadInfo {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard kr == KERN_SUCCESS, let info = cpuInfo, cpuCount > 0 else {
            return CPULoadInfo(
                overallPercent: 0,
                perCorePercent: [],
                userPercent: 0,
                systemPercent: 0,
                idlePercent: 100
            )
        }

        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        lock.lock()
        defer { lock.unlock() }

        var perCore: [Double] = []
        var totalUser: Double = 0
        var totalSystem: Double = 0
        var totalIdle: Double = 0
        var totalNice: Double = 0

        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(cpuCount) {
            let base = i * stride
            let user = Double(info[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)])

            if let prev = previous, previousCoreCount == cpuCount {
                let pBase = i * stride
                let dUser = user - Double(prev[pBase + Int(CPU_STATE_USER)])
                let dSystem = system - Double(prev[pBase + Int(CPU_STATE_SYSTEM)])
                let dIdle = idle - Double(prev[pBase + Int(CPU_STATE_IDLE)])
                let dNice = nice - Double(prev[pBase + Int(CPU_STATE_NICE)])
                let sum = dUser + dSystem + dIdle + dNice
                let busy = sum > 0 ? (dUser + dSystem + dNice) / sum * 100 : 0
                perCore.append((busy * 10).rounded() / 10)
                totalUser += dUser
                totalSystem += dSystem
                totalIdle += dIdle
                totalNice += dNice
            } else {
                perCore.append(0)
            }
        }

        // Keep a copy for next delta
        let copyCount = Int(cpuInfoCount)
        let copy = UnsafeMutablePointer<integer_t>.allocate(capacity: copyCount)
        copy.initialize(from: info, count: copyCount)
        if let old = previous {
            old.deallocate()
        }
        previous = copy
        previousCount = cpuInfoCount
        previousCoreCount = cpuCount

        let total = totalUser + totalSystem + totalIdle + totalNice
        let overall = total > 0 ? (totalUser + totalSystem + totalNice) / total * 100 : 0
        let userPct = total > 0 ? totalUser / total * 100 : 0
        let sysPct = total > 0 ? totalSystem / total * 100 : 0
        let idlePct = total > 0 ? totalIdle / total * 100 : 100

        return CPULoadInfo(
            overallPercent: (overall * 10).rounded() / 10,
            perCorePercent: perCore,
            userPercent: (userPct * 10).rounded() / 10,
            systemPercent: (sysPct * 10).rounded() / 10,
            idlePercent: (idlePct * 10).rounded() / 10
        )
    }
}
