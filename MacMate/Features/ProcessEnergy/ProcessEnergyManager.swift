import Foundation
import Combine
import AppKit
import Darwin

// MARK: - Process Energy & Thermal Monitor

public struct HeavyProcess: Identifiable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let cpu: Double
    public var isFrozen: Bool

    public static func == (lhs: HeavyProcess, rhs: HeavyProcess) -> Bool {
        lhs.pid == rhs.pid && lhs.cpu == rhs.cpu && lhs.isFrozen == rhs.isFrozen
    }
}

private struct ProcessCPUSample {
    let totalNanoseconds: UInt64
    let timestamp: TimeInterval
}

@MainActor
public class ProcessEnergyManager: ObservableObject {
    public static let shared = ProcessEnergyManager()

    @Published public var processes: [HeavyProcess] = []
    @Published public var frozenPIDs: Set<Int32> = []
    @Published public var isScanning: Bool = false
    @Published public var lastRefreshed: Date = Date()

    private var timer: Timer?
    private var cpuSamples: [Int32: ProcessCPUSample] = [:]
    private var hasCPUBaseline = false
    private var isPopoverVisible = false
    private var isProcessSectionVisible = false

    private let ignoredNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "sysmond", "MacMate",
        "Activity Monitor", "coreaudiod", "loginwindow", "fseventsd",
        "distnoted", "powerd", "opendirectoryd", "trustd", "UserEventAgent",
        "sandboxd", "diskarbitrationd", "mds", "mds_stores", "mdworker",
        "notifyd", "cfprefsd", "logd", "symptomsd", "containermanagerd",
        "Finder", "Dock", "SystemUIServer", "ControlCenter", "NotificationCenter", "Spotlight"
    ]

    private init() {}

    public func startAutoRefresh() {
        setProcessSectionVisible(true)
    }

    public func stopAutoRefresh() {
        setProcessSectionVisible(false)
    }

    public func setPopoverVisible(_ visible: Bool) {
        guard isPopoverVisible != visible else { return }
        isPopoverVisible = visible
        updatePollingState()
    }

    public func setProcessSectionVisible(_ visible: Bool) {
        guard isProcessSectionVisible != visible else { return }
        isProcessSectionVisible = visible
        updatePollingState()
    }

    private func updatePollingState() {
        guard isPopoverVisible && isProcessSectionVisible else {
            timer?.invalidate()
            timer = nil
            if !isScanning {
                cpuSamples.removeAll(keepingCapacity: true)
                hasCPUBaseline = false
            }
            return
        }
        guard timer == nil, !isScanning else { return }

        refreshProcesses()
    }

    private func scheduleNextRefresh(after interval: TimeInterval) {
        guard isPopoverVisible && isProcessSectionVisible else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timer = nil
                self?.refreshProcesses()
            }
        }
    }

    public func refreshProcesses() {
        guard !isScanning else { return }
        isScanning = true

        let currentFrozen = self.frozenPIDs
        let ignored = self.ignoredNames
        let previousSamples = self.cpuSamples

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let processCount = max(0, proc_listallpids(nil, 0))
            var pids = [Int32](repeating: 0, count: Int(processCount) + 32)
            let actualCount = pids.withUnsafeMutableBytes { buffer in
                proc_listallpids(buffer.baseAddress, Int32(buffer.count))
            }
            if actualCount > 0 {
                pids = Array(pids.prefix(Int(actualCount)))
            } else {
                pids.removeAll(keepingCapacity: true)
            }

            var nextSamples: [Int32: ProcessCPUSample] = [:]
            var found: [HeavyProcess] = []
            for pid in pids where pid > 0 {
                var taskInfo = proc_taskinfo()
                let infoSize = proc_pidinfo(
                    pid,
                    PROC_PIDTASKINFO,
                    0,
                    &taskInfo,
                    Int32(MemoryLayout<proc_taskinfo>.size)
                )
                guard infoSize == MemoryLayout<proc_taskinfo>.size else { continue }

                let totalCPU = taskInfo.pti_total_user + taskInfo.pti_total_system
                let previous = previousSamples[pid]
                nextSamples[pid] = ProcessCPUSample(totalNanoseconds: totalCPU, timestamp: now)
                guard let previous,
                      now > previous.timestamp,
                      totalCPU >= previous.totalNanoseconds else { continue }
                let elapsed = now - previous.timestamp
                let cpu = Double(totalCPU - previous.totalNanoseconds) / (elapsed * 1_000_000_000) * 100
                guard cpu > 0 else { continue }

                var nameBuffer = [CChar](repeating: 0, count: 2_000)
                let nameLength = nameBuffer.withUnsafeMutableBufferPointer {
                    proc_name(pid, $0.baseAddress, UInt32($0.count))
                }
                guard nameLength > 0 else { continue }
                let rawName = String(cString: nameBuffer)
                let shortName = (rawName as NSString).lastPathComponent
                guard !ignored.contains(shortName), !ignored.contains(rawName) else { continue }
                found.append(HeavyProcess(
                    pid: pid,
                    name: shortName,
                    cpu: cpu,
                    isFrozen: currentFrozen.contains(pid)
                ))
            }

            found.sort { $0.cpu > $1.cpu }
            let topProcesses = Array(found.prefix(6))
            DispatchQueue.main.async {
                self.isScanning = false
                guard self.isPopoverVisible && self.isProcessSectionVisible else {
                    self.cpuSamples.removeAll(keepingCapacity: true)
                    self.hasCPUBaseline = false
                    return
                }

                self.cpuSamples = nextSamples
                self.processes = topProcesses
                self.lastRefreshed = Date()
                let nextInterval: TimeInterval = self.hasCPUBaseline ? 5.0 : 1.0
                self.hasCPUBaseline = true
                self.scheduleNextRefresh(after: nextInterval)
            }
        }
    }

    // MARK: - Actions: Safe Throttle & Safe Freeze

    public func freezeProcess(pid: Int32, autoResumeAfter: TimeInterval? = 15.0) {
        // SAFETY GUARD: NEVER freeze the user's active frontmost application (e.g. Chrome, Safari, Word)
        if let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier, frontPID == pid {
            // Lower priority instead of freezing active app
            setpriority(PRIO_PROCESS, id_t(pid), 20)
            return
        }

        kill(pid, SIGSTOP)
        frozenPIDs.insert(pid)
        updateLocalState(pid: pid, isFrozen: true)

        // Safety Auto-Resume: Automatically resume after timeout so app never hangs indefinitely
        if let timeout = autoResumeAfter, timeout > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                if self?.frozenPIDs.contains(pid) == true {
                    self?.resumeProcess(pid: pid)
                }
            }
        }
    }

    public func resumeProcess(pid: Int32) {
        kill(pid, SIGCONT)
        setpriority(PRIO_PROCESS, id_t(pid), 0)
        frozenPIDs.remove(pid)
        updateLocalState(pid: pid, isFrozen: false)
    }

    public func terminateProcess(pid: Int32) {
        kill(pid, SIGTERM)
        frozenPIDs.remove(pid)
        processes.removeAll { $0.pid == pid }
    }

    // SAFE Software Cooling for Fanless Macs:
    // Throttles background processes using renice +20 (idle priority) and pauses only background tasks with auto-resume.
    // NEVER freezes the frontmost active app!
    public func optimizeBackgroundConsumers() {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        for p in processes {
            // Never touch the frontmost app the user is actively viewing
            if p.pid == frontPID { continue }

            // Set priority to lowest (idle cycles only) to immediately stop CPU burning
            setpriority(PRIO_PROCESS, id_t(p.pid), 20)
        }

        // For top background processes, temporarily pause for 8 seconds to drop chip temperature, then auto-resume
        let backgroundCandidates = processes.filter { $0.pid != frontPID && !$0.isFrozen }
        for p in backgroundCandidates.prefix(2) {
            freezeProcess(pid: p.pid, autoResumeAfter: 8.0)
        }
    }

    public func freezeTopConsumers() {
        optimizeBackgroundConsumers()
    }

    private func updateLocalState(pid: Int32, isFrozen: Bool) {
        if let idx = processes.firstIndex(where: { $0.pid == pid }) {
            let p = processes[idx]
            processes[idx] = HeavyProcess(pid: p.pid, name: p.name, cpu: isFrozen ? 0.0 : p.cpu, isFrozen: isFrozen)
        }
    }
}
