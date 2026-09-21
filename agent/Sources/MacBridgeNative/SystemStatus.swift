import Foundation
import Darwin
import MacBridgeCore

/// Small on-demand health snapshot. No identifiers, network addresses or file names.
public enum SystemStatus {
    static func boundedUsage(total: UInt64, active: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
        let pages = active.addingReportingOverflow(wired)
        let combined = pages.partialValue.addingReportingOverflow(compressed)
        let bytes = combined.partialValue.multipliedReportingOverflow(by: pageSize)
        return pages.overflow || combined.overflow || bytes.overflow ? total : min(total, bytes.partialValue)
    }
    public static func read() -> JSON {
        let process = ProcessInfo.processInfo
        let version = process.operatingSystemVersion
        var memory: JSON = .null
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var pageSize: vm_size_t = 0
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        if result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS {
            let used = boundedUsage(total: process.physicalMemory, active: UInt64(stats.active_count), wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count), pageSize: UInt64(pageSize))
            memory = .object(["total_bytes": .number(Double(process.physicalMemory)), "used_bytes": .number(Double(used))])
        }
        var storage: JSON = .null
        // The user's home volume, not the read-only system volume or external disks.
        if let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity, total > 0, free >= 0 {
            storage = .object(["total_bytes": .number(Double(total)), "available_bytes": .number(Double(min(total, free)))])
        }
        var boot = timeval(); var size = MemoryLayout<timeval>.size
        var uptime: JSON = .null
        if sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 {
            uptime = .number(max(0, floor(Date().timeIntervalSince1970 - Double(boot.tv_sec))))
        }
        let thermal: String
        switch process.thermalState {
        case .nominal: thermal = "normal"
        case .fair: thermal = "warm"
        case .serious: thermal = "hot"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        return .object(["macos_version": .string("\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"),
                        "uptime_seconds": uptime, "low_power_mode": .bool(process.isLowPowerModeEnabled),
                        "thermal_state": .string(thermal), "memory": memory, "storage": storage])
    }
}
