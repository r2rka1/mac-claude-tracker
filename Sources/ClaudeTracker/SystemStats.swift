import Darwin
import Foundation

struct ProcInfo: Identifiable {
    let pid: Int
    let cpu: Double      // percent of one core, as reported by ps
    let rssBytes: UInt64
    let name: String
    var id: Int { pid }
}

struct SystemSnapshot {
    var cpu: Double = 0          // 0...1 across all cores
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var load: [Double] = [0, 0, 0]
    var coreCount: Int = ProcessInfo.processInfo.activeProcessorCount
    var memUsed: UInt64 = 0
    var memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var swapUsed: UInt64 = 0
    var diskFree: UInt64 = 0
    var diskTotal: UInt64 = 0
    var procCount: Int = 0
    var topCPU: [ProcInfo] = []
    var topMem: [ProcInfo] = []

    var memFraction: Double { memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal) }
    var diskFraction: Double { diskTotal == 0 ? 0 : 1 - Double(diskFree) / Double(diskTotal) }
}

struct CPUTicks {
    // The kernel counters are 32-bit and wrap; keep them 32-bit so deltas wrap correctly.
    var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
}

enum SystemStats {
    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: info.cpu_ticks.0, system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    /// Returns (total, user, system) as fractions 0...1 between two samples.
    static func cpuUsage(from a: CPUTicks, to b: CPUTicks) -> (Double, Double, Double) {
        let user = Double(b.user &- a.user) + Double(b.nice &- a.nice)
        let sys = Double(b.system &- a.system)
        let idle = Double(b.idle &- a.idle)
        let total = user + sys + idle
        guard total > 0 else { return (0, 0, 0) }
        return ((user + sys) / total, user / total, sys / total)
    }

    /// Used memory the way Activity Monitor counts it: app + wired + compressed.
    static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = internalPages > purgeable ? internalPages - purgeable : 0
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    static func disk() -> (free: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/System/Volumes/Data")
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ]
        guard let v = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        return (
            UInt64(max(0, v.volumeAvailableCapacityForImportantUsage ?? 0)),
            UInt64(max(0, v.volumeTotalCapacity ?? 0))
        )
    }

    static func loadAverage() -> [Double] {
        var l = [Double](repeating: 0, count: 3)
        getloadavg(&l, 3)
        return l
    }

    static func processes() -> [ProcInfo] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aceo", "pid=,pcpu=,rss=,comm="]
        p.environment = ["LC_ALL": "C"]  // keep the decimal point a point
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return [] }
        var result: [ProcInfo] = []
        result.reserveCapacity(800)
        for line in out.split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard f.count == 4, let pid = Int(f[0]), let cpu = Double(f[1]),
                let rss = UInt64(f[2])
            else { continue }
            result.append(
                ProcInfo(
                    pid: pid, cpu: cpu, rssBytes: rss * 1024,
                    name: f[3].trimmingCharacters(in: .whitespaces)))
        }
        return result
    }
}

enum Fmt {
    static func bytes(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 100 { return String(format: "%.0fG", gb) }
        if gb >= 1 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(b) / 1_048_576)
    }

    static func pct(_ f: Double) -> String { String(format: "%.0f%%", f * 100) }

    static func age(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "–" }
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    static func tokens(_ n: Int) -> String {
        n >= 1000 ? "\(n / 1000)k" : "\(n)"
    }
}
