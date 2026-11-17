import Darwin
import FormalCore

struct ProcessGroupMonitor {
    let limits: ToolProcessLimits
    private(set) var peakResident: UInt64 = 0
    private(set) var peakProcesses = 0
    private(set) var cpuSeconds: Double = 0
    mutating func sample(_ group: pid_t) throws {
        // libproc borrows initialized storage synchronously. Neither pointer escapes.
        var processes = [pid_t](repeating: 0, count: limits.maximumProcesses + 1)
        let count = processes.withUnsafeMutableBytes { proc_listpgrppids(group, $0.baseAddress, Int32($0.count)) }
        guard count >= 0 else { throw FormalDiagnostic(.toolFailure, "Cannot inspect owned process group") }
        let owned = Set(processes.prefix(max(0, Int(count))))
        guard owned.count <= limits.maximumProcesses else { throw ToolResourceLimit.processes }
        var resident: UInt64 = 0, cpu = 0.0
        for pid in owned where pid > 0 {
            var usage = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            if result != 0 {
                if errno == ESRCH || errno == ENOENT { continue }
                throw FormalDiagnostic(.toolFailure, "Cannot inspect owned process usage")
            }
            guard usage.ri_resident_size <= limits.maximumResidentBytes, resident <= limits.maximumResidentBytes - usage.ri_resident_size else { throw ToolResourceLimit.memory }
            resident += usage.ri_resident_size
            cpu += (Double(usage.ri_user_time) + Double(usage.ri_system_time) + Double(usage.ri_child_user_time) + Double(usage.ri_child_system_time)) / 1e9
        }
        peakResident = max(peakResident, resident); peakProcesses = max(peakProcesses, owned.count); cpuSeconds = max(cpuSeconds, cpu)
        guard cpuSeconds <= limits.maximumCPUSeconds else { throw ToolResourceLimit.cpu }
    }
    mutating func finish(_ usage: rusage) throws {
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        cpuSeconds = max(cpuSeconds, user + system)
        guard cpuSeconds <= limits.maximumCPUSeconds else { throw ToolResourceLimit.cpu }
    }
    var measurements: ToolMeasurements { ToolMeasurements(sampledPeakResidentBytes: peakResident, sampledPeakProcesses: peakProcesses, cpuSeconds: cpuSeconds) }
}
