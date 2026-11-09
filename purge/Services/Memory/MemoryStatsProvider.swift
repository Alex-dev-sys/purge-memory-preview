import Darwin
import Foundation

nonisolated protocol MemoryStatsProviding: Sendable {
    func sample() async -> MemorySnapshot?
}

actor MemoryStatsProvider: MemoryStatsProviding {
    func sample() async -> MemorySnapshot? {
        var pageSize: vm_size_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let capacity = Int(count)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        let requiredBytes = (MemoryLayout<vm_statistics64>.offset(of: \.internal_page_count) ?? MemoryLayout<vm_statistics64>.size) + MemoryLayout<natural_t>.size
        guard status == KERN_SUCCESS, Int(count) * MemoryLayout<integer_t>.size >= requiredBytes else { return nil }
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &size, nil, 0) == 0 else { return nil }
        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0
        return MemoryAccounting.snapshot(total: total, pageSize: UInt64(pageSize),
            free: UInt64(info.free_count), speculative: UInt64(info.speculative_count),
            internalPages: UInt64(info.internal_page_count), externalPages: UInt64(info.external_page_count),
            purgeable: UInt64(info.purgeable_count), wired: UInt64(info.wire_count),
            compressed: UInt64(info.compressor_page_count), swap: hasSwap ? swap.xsu_used : nil)
    }
}
