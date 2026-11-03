import Foundation
import IOKit
import Combine
import AppKit

private func isAppleSiliconMac() -> Bool {
    var supported: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("hw.optional.arm64", &supported, &size, nil, 0) == 0 && supported == 1
}

// MARK: - Sensor Model

public struct SensorReading: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let temp: Double
    public let category: String
}

// MARK: - Native Apple Silicon IOHID Temperature Reader

private typealias ClientRef = OpaquePointer
private typealias ServiceRef = OpaquePointer
private typealias EventRef = OpaquePointer

private typealias FnCreate = @convention(c) (CFAllocator?) -> ClientRef?
private typealias FnCreateWithType = @convention(c) (CFAllocator?, UInt32, CFDictionary?) -> ClientRef?
private typealias FnSetMatching = @convention(c) (ClientRef, CFDictionary?) -> Void
private typealias FnCopyServices = @convention(c) (ClientRef) -> CFArray?
private typealias FnCopyProperty = @convention(c) (ServiceRef, CFString) -> CFTypeRef?
private typealias FnCopyEvent = @convention(c) (ServiceRef, Int64, Int32, Int64) -> EventRef?
private typealias FnGetFloat = @convention(c) (EventRef, UInt32) -> Double

private class AppleSiliconHIDReader {
    private var client: ClientRef?
    private var cachedServices: [ServiceRef] = []
    private var servicesContainer: CFArray?
    private var lastDiscoveryTime: TimeInterval = 0
    private var didTryTypedClientFallback = false

    private var fnCreate: FnCreate?
    private var fnCreateWithType: FnCreateWithType?
    private var fnSetMatching: FnSetMatching?
    private var fnCopyServices: FnCopyServices?
    private var fnCopyProperty: FnCopyProperty?
    private var fnCopyEvent: FnCopyEvent?
    private var fnGetFloat: FnGetFloat?

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return }
        if let s = dlsym(handle, "IOHIDEventSystemClientCreate") { fnCreate = unsafeBitCast(s, to: FnCreate.self) }
        if let s = dlsym(handle, "IOHIDEventSystemClientCreateWithType") { fnCreateWithType = unsafeBitCast(s, to: FnCreateWithType.self) }
        if let s = dlsym(handle, "IOHIDEventSystemClientSetMatching") { fnSetMatching = unsafeBitCast(s, to: FnSetMatching.self) }
        if let s = dlsym(handle, "IOHIDEventSystemClientCopyServices") { fnCopyServices = unsafeBitCast(s, to: FnCopyServices.self) }
        if let s = dlsym(handle, "IOHIDServiceClientCopyProperty") { fnCopyProperty = unsafeBitCast(s, to: FnCopyProperty.self) }
        if let s = dlsym(handle, "IOHIDServiceClientCopyEvent") { fnCopyEvent = unsafeBitCast(s, to: FnCopyEvent.self) }
        if let s = dlsym(handle, "IOHIDEventGetFloatValue") { fnGetFloat = unsafeBitCast(s, to: FnGetFloat.self) }
    }

    func readTemperatures() -> (cpuAvg: Double, cpuPeak: Double, gpuAvg: Double, battery: Double, nand: Double, hotspot: Double, sensors: [SensorReading]) {
        guard let copyServ = fnCopyServices, let copyProp = fnCopyProperty,
              let copyEvt = fnCopyEvent, let getFloat = fnGetFloat else {
            return (0, 0, 0, 0, 0, 0, [])
        }

        let now = ProcessInfo.processInfo.systemUptime
        if client == nil {
            if let create = fnCreate {
                client = create(kCFAllocatorDefault)
            }
            if client == nil, let createWithType = fnCreateWithType {
                client = createWithType(kCFAllocatorDefault, 1, nil)
                didTryTypedClientFallback = true
            }
            if let client, let setMatching = fnSetMatching {
                let matching = [
                    "PrimaryUsagePage": 0xff00,
                    "PrimaryUsage": 5
                ] as CFDictionary
                setMatching(client, matching)
            }
        }
        guard let c = client else { return (0, 0, 0, 0, 0, 0, []) }

        // Refresh services every 60s. Keep the returned array alive because the
        // cached service pointers are owned by it.
        if lastDiscoveryTime == 0 || (now - lastDiscoveryTime > 60) {
            cachedServices.removeAll(keepingCapacity: true)
            servicesContainer = copyServ(c)
            if let servCF = servicesContainer {
                appendServices(from: servCF, to: &cachedServices)
            }

            if cachedServices.isEmpty,
               !didTryTypedClientFallback,
               let createWithType = fnCreateWithType {
                didTryTypedClientFallback = true
                let fallbackClient = createWithType(kCFAllocatorDefault, 1, nil)
                if let fallbackClient {
                    if let setMatching = fnSetMatching {
                        let matching = [
                            "PrimaryUsagePage": 0xff00,
                            "PrimaryUsage": 5
                        ] as CFDictionary
                        setMatching(fallbackClient, matching)
                    }
                    if let fallbackServices = copyServ(fallbackClient),
                       CFArrayGetCount(fallbackServices) > 0 {
                        client = fallbackClient
                        servicesContainer = fallbackServices
                        appendServices(from: fallbackServices, to: &cachedServices)
                    }
                }
            }
            lastDiscoveryTime = now
        }

        var cpuTemps: [Double] = []
        var gpuTemps: [Double] = []
        var batteryTemps: [Double] = []
        var nandTemps: [Double] = []
        var hotspotTemps: [Double] = []
        var sensorList: [SensorReading] = []

        let kIOHIDEventTypeTemperature: Int64 = 15
        let kIOHIDEventFieldTemperatureValue: UInt32 = (15 << 16) | 0

        for s in cachedServices {
            guard let pRef = copyProp(s, "Product" as CFString),
                  let name = pRef as? String else { continue }

            guard let evt = copyEvt(s, kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let temp = getFloat(evt, kIOHIDEventFieldTemperatureValue)
            guard temp > 15.0 && temp < 125.0 else { continue }

            let normalizedName = name.lowercased()
            if normalizedName.hasPrefix("pmu tdie") || normalizedName.hasPrefix("pmu2 tdie") {
                cpuTemps.append(temp)
                let coreIdx = name.replacingOccurrences(of: "PMU tdie", with: "").replacingOccurrences(of: "PMU2 tdie", with: " (P-Core ")
                let label = name.contains("PMU2") ? "CPU P-Core \(coreIdx.replacingOccurrences(of: " (P-Core ", with: ""))" : "CPU Core \(coreIdx)"
                sensorList.append(SensorReading(name: name, displayName: label, temp: temp, category: "CPU"))
            } else if normalizedName.hasPrefix("pmu tdev") || normalizedName.hasPrefix("pmu2 tdev") || normalizedName.contains("gpu") {
                gpuTemps.append(temp)
                let gpuIdx = name.replacingOccurrences(of: "PMU tdev", with: "").replacingOccurrences(of: "PMU2 tdev", with: " Cụm ")
                sensorList.append(SensorReading(name: name, displayName: "GPU Cụm \(gpuIdx)", temp: temp, category: "GPU"))
            } else if normalizedName.contains("battery") {
                batteryTemps.append(temp)
                sensorList.append(SensorReading(name: name, displayName: "Pin Cell (Gas Gauge)", temp: temp, category: "Pin"))
            } else if normalizedName.contains("nand") || normalizedName.contains("ssd") {
                nandTemps.append(temp)
                sensorList.append(SensorReading(name: name, displayName: "SSD NVMe Flash", temp: temp, category: "Ổ cứng"))
            } else if normalizedName.contains("tcal") || normalizedName.contains("board") {
                hotspotTemps.append(temp)
                sensorList.append(SensorReading(name: name, displayName: "Hotspot Bo mạch", temp: temp, category: "Bo mạch"))
            }
        }

        let cpuAvg = cpuTemps.isEmpty ? 0.0 : (cpuTemps.reduce(0, +) / Double(cpuTemps.count))
        let cpuPeak = cpuTemps.max() ?? 0.0
        let gpuAvg = gpuTemps.isEmpty ? 0.0 : (gpuTemps.reduce(0, +) / Double(gpuTemps.count))
        let bat = batteryTemps.isEmpty ? 0.0 : (batteryTemps.reduce(0, +) / Double(batteryTemps.count))
        let nand = nandTemps.isEmpty ? 0.0 : (nandTemps.reduce(0, +) / Double(nandTemps.count))
        let hot = hotspotTemps.isEmpty ? 0.0 : (hotspotTemps.reduce(0, +) / Double(hotspotTemps.count))

        return (cpuAvg, cpuPeak, gpuAvg, bat, nand, hot, sensorList)
    }

    private func appendServices(from array: CFArray, to services: inout [ServiceRef]) {
        let count = CFArrayGetCount(array)
        for index in 0..<count {
            let service = unsafeBitCast(CFArrayGetValueAtIndex(array, index), to: ServiceRef.self)
            services.append(service)
        }
    }

    deinit {
        cachedServices.removeAll()
        servicesContainer = nil
    }
}

// MARK: - Intel SMC Temperature Reader

private class IntelSMCReader {
    func readTemperatures() -> (cpuAvg: Double, cpuPeak: Double, gpuAvg: Double, battery: Double, nand: Double, hotspot: Double, sensors: [SensorReading]) {
        guard let helper = Bundle.main.path(forResource: "smc", ofType: nil) else {
            return (0, 0, 0, 0, 0, 0, [])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = ["--temperatures"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return (0, 0, 0, 0, 0, 0, [])
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return (0, 0, 0, 0, 0, 0, [])
        }

        var readings: [String: Double] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let temperature = Double(parts[1]) else { continue }
            readings[String(parts[0])] = temperature
        }

        let coreKeys = (0...7).map { "TC\($0)C" }
        let cpuKeys = coreKeys.filter { readings[$0] != nil }
        let selectedCPUKeys = cpuKeys.isEmpty
            ? ["TC0D", "TC0E", "TC0F", "TC0J", "TC0P", "TC0H"].filter { readings[$0] != nil }
            : cpuKeys
        let cpuTemperatures = selectedCPUKeys.compactMap { readings[$0] }
        let cpuPeak = readings.filter {
            let key = $0.key.uppercased()
            return key.hasPrefix("TC") && key != "TCGC"
        }.values.max() ?? 0
        let gpuTemperatures = readings.filter {
            let key = $0.key.uppercased()
            return key.hasPrefix("TG") || key == "TCGC"
        }.values.map { $0 }
        let storageTemperatures = readings.filter { $0.key.uppercased().hasPrefix("TH") }.values.map { $0 }
        let batteryTemperatures = ["TB0T", "TB1T", "TB2T"].compactMap { readings[$0] }
        let boardTemperatures = readings.filter {
            let key = $0.key.uppercased()
            return key.hasPrefix("TM") || key.hasPrefix("TP") || key.hasPrefix("TS") || key.hasPrefix("TA")
        }.values.map { $0 }

        let sensors = readings.keys.sorted().compactMap { key -> SensorReading? in
            guard let temperature = readings[key] else { return nil }
            let normalizedKey = key.uppercased()
            let category: String
            let label: String
            if normalizedKey.hasPrefix("TC") {
                category = "CPU"
                label = "CPU \(key)"
            } else if normalizedKey.hasPrefix("TG") || normalizedKey == "TCGC" {
                category = "GPU"
                label = "GPU \(key)"
            } else if normalizedKey.hasPrefix("TB") {
                category = "Pin"
                label = "Pin \(key)"
            } else if normalizedKey.hasPrefix("TH") {
                category = "Ổ cứng"
                label = "Ổ cứng \(key)"
            } else {
                category = "Bo mạch"
                label = "Bo mạch \(key)"
            }
            return SensorReading(name: key, displayName: label, temp: temperature, category: category)
        }

        func average(_ values: [Double]) -> Double {
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        return (
            average(cpuTemperatures), cpuPeak,
            average(gpuTemperatures), average(batteryTemperatures),
            average(storageTemperatures),
            average(boardTemperatures), sensors
        )
    }
}

// MARK: - Background Thermal Sampling

private struct ThermalMetricsSnapshot: Sendable {
    let cpuAvg: Double
    let cpuPeak: Double
    let gpuAvg: Double
    let battery: Double
    let ssd: Double
    let hotspot: Double
    let sensors: [SensorReading]
    let stateDescription: String
    let isThrottling: Bool
    let backend: String
}

/// Serializes native sensor reads away from the MainActor.
private actor ThermalMetricsReader {
    private let hidReader = AppleSiliconHIDReader()
    private let smcReader = IntelSMCReader()

    func readSnapshot() -> ThermalMetricsSnapshot {
        let appleSilicon = isAppleSiliconMac()
        let reading = appleSilicon ? hidReader.readTemperatures() : smcReader.readTemperatures()
        let (cpu, peak, gpu, bat, nand, hot, sensors) = reading

        let stateDescription: String
        let throttling: Bool
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            stateDescription = "Mát mẻ (Bình thường)"
            throttling = false
        case .fair:
            stateDescription = "Ấm nhẹ (Tải vừa)"
            throttling = false
        case .serious:
            stateDescription = "Nóng (Đang giảm xung nhẹ)"
            throttling = true
        case .critical:
            stateDescription = "Rất nóng (Thermal Throttling tối đa!)"
            throttling = true
        @unknown default:
            stateDescription = "Bình thường"
            throttling = false
        }

        return ThermalMetricsSnapshot(
            cpuAvg: cpu,
            cpuPeak: peak,
            gpuAvg: gpu,
            battery: bat,
            ssd: nand,
            hotspot: hot,
            sensors: sensors,
            stateDescription: stateDescription,
            isThrottling: throttling,
            backend: appleSilicon ? "IOHID" : "SMC"
        )
    }
}

// MARK: - Thermal Manager Engine (Temperature Monitoring Only)

/// Reads Apple Silicon HID/PMU or Intel SMC temperature sensors for the UI.
///
/// NOTE: Fan control was intentionally removed in v1.5.2. MacMate no longer
/// writes SMC fan keys or installs a privileged helper for fan speed changes.
@MainActor
public class ThermalManager: ObservableObject {
    public static let shared = ThermalManager()
    public let isIntelMac = !isAppleSiliconMac()

    @Published public var machineModelName: String = "Mac"

    // Real-Time Temperatures (°C)
    @Published public var cpuAvgTemp: Double = 0.0
    @Published public var cpuPeakTemp: Double = 0.0
    @Published public var gpuAvgTemp: Double = 0.0
    @Published public var batteryTemp: Double = 0.0
    @Published public var ssdTemp: Double = 0.0
    @Published public var hotspotTemp: Double = 0.0

    // Detailed Sensor Breakdown
    @Published public var detailedSensors: [SensorReading] = []
    @Published public var isDetailExpanded: Bool = false

    // UI View State (Stored here to prevent CommandLineTools SwiftUIMacros @State crash)
    @Published public var selectedSection: Int = 0 // 0: Pin & Nguồn SMC, 1: Nhiệt độ & Cảm biến
    @Published public var isRefreshing: Bool = false

    // Thermal Throttling & Status
    @Published public var thermalStateDescription: String = "Mát mẻ (Bình thường)"
    @Published public var isThrottling: Bool = false

    // Menu Bar live temperature pill
    @Published public var showMenuBarMetrics: Bool = UserDefaults.standard.bool(forKey: "show_menubar_thermal") {
        didSet {
            UserDefaults.standard.set(showMenuBarMetrics, forKey: "show_menubar_thermal")
            updateMenuBarDisplay()
        }
    }
    public var onMenuBarUpdate: (@MainActor (String?) -> Void)?

    private let metricsReader = ThermalMetricsReader()
    private var pollTimer: Timer?
    private var isPopoverVisible = false
    private var isMetricsReadInFlight = false
    private var hasPendingMetricsRead = false
    private var hasLoggedSensorStatus = false
    private let debugLogging = ProcessInfo.processInfo.environment["MACMATE_THERMAL_DEBUG"] == "1"

    private init() {
        loadMachineHardwareInfo()
        refreshMetrics()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    private func loadMachineHardwareInfo() {
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)
        let modelLower = modelString.lowercased()

        if modelLower.contains("air") ||
            modelString.hasPrefix("Mac14,2") ||
            modelString.hasPrefix("Mac14,15") ||
            modelString.hasPrefix("Mac15,12") ||
            modelString.hasPrefix("Mac15,13") {
            self.machineModelName = "MacBook Air"
        } else if modelString.hasPrefix("MacBook8,") ||
                    modelString.hasPrefix("MacBook9,") ||
                    modelString.hasPrefix("MacBook10,") {
            self.machineModelName = "MacBook (12-inch)"
        } else if modelLower.contains("mini") || modelString == "Mac14,3" || modelString == "Mac14,12" ||
                    modelString.hasPrefix("Mac16,10") || modelString.hasPrefix("Mac16,11") || modelString.hasPrefix("Mac16,15") {
            self.machineModelName = "Mac mini"
        } else if modelLower.contains("studio") || modelString.hasPrefix("Mac13,") ||
                    modelString == "Mac14,13" || modelString == "Mac14,14" {
            self.machineModelName = "Mac Studio"
        } else if modelLower.contains("imac") || modelString == "Mac15,4" || modelString == "Mac15,5" ||
                    modelString == "Mac16,2" || modelString == "Mac16,3" {
            self.machineModelName = "iMac"
        } else if modelLower.contains("pro") ||
                    modelString.hasPrefix("MacBookPro") ||
                    modelString.hasPrefix("Mac14,5") || modelString.hasPrefix("Mac14,6") ||
                    modelString.hasPrefix("Mac14,7") || modelString.hasPrefix("Mac14,9") ||
                    modelString.hasPrefix("Mac14,10") || modelString.hasPrefix("Mac15,") ||
                    modelString.hasPrefix("Mac16,") {
            self.machineModelName = "MacBook Pro"
        } else {
            self.machineModelName = modelString.isEmpty ? "Mac" : modelString
        }
    }

    // MARK: - Polling & Refresh Metrics

    private func startPolling() {
        guard isPopoverVisible || showMenuBarMetrics else { return }
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMetrics()
            }
        }
    }

    public func setPopoverVisible(_ visible: Bool) {
        guard isPopoverVisible != visible else { return }
        isPopoverVisible = visible
        if visible {
            refreshMetrics()
        }
        startPolling()
    }

    private func updatePollingState() {
        if isPopoverVisible || showMenuBarMetrics {
            startPolling()
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    public func refreshMetrics() {
        guard !isMetricsReadInFlight else {
            hasPendingMetricsRead = true
            return
        }
        isMetricsReadInFlight = true
        let reader = metricsReader

        Task { @MainActor [weak self] in
            let snapshot = await reader.readSnapshot()
            guard let self else { return }
            self.isMetricsReadInFlight = false
            self.apply(snapshot)
            if self.hasPendingMetricsRead {
                self.hasPendingMetricsRead = false
                self.refreshMetrics()
            }
        }
    }

    /// Applies observable state and triggers menu-bar UI only on MainActor.
    private func apply(_ snapshot: ThermalMetricsSnapshot) {
        cpuAvgTemp = snapshot.cpuAvg
        cpuPeakTemp = snapshot.cpuPeak
        gpuAvgTemp = snapshot.gpuAvg
        batteryTemp = snapshot.battery
        ssdTemp = snapshot.ssd
        hotspotTemp = snapshot.hotspot
        detailedSensors = snapshot.sensors
        thermalStateDescription = snapshot.stateDescription
        isThrottling = snapshot.isThrottling

        if debugLogging {
            let summary = snapshot.sensors
                .map { "\($0.name)=\(String(format: "%.1f", $0.temp))°C" }
                .joined(separator: ", ")
            appLog("🌡 Thermal: CPU \(String(format: "%.1f", snapshot.cpuAvg))°C, GPU \(String(format: "%.1f", snapshot.gpuAvg))°C, sensors=[\(summary)]")
        } else if !hasLoggedSensorStatus {
            hasLoggedSensorStatus = true
            if snapshot.cpuAvg > 0 || !snapshot.sensors.isEmpty {
                appLog("🌡 Thermal: backend \(snapshot.backend) hoạt động, đọc được \(snapshot.sensors.count) cảm biến.")
            } else {
                appLog("⚠️ Thermal: \(snapshot.backend) không trả về cảm biến nhiệt.")
            }
        }

        updateMenuBarDisplay()
    }

    /// Objective-C notifications execute on the posting thread. This entry point
    /// must therefore be nonisolated and explicitly hop to MainActor.
    @objc nonisolated private func thermalStateChanged() {
        Task { @MainActor [weak self] in
            self?.refreshMetrics()
        }
    }

    public func updateMenuBarDisplay() {
        updatePollingState()
        guard showMenuBarMetrics else {
            onMenuBarUpdate?(nil)
            return
        }
        let temp = cpuAvgTemp > 0 ? Int(cpuAvgTemp) : (cpuPeakTemp > 0 ? Int(cpuPeakTemp) : 0)
        guard temp > 0 else {
            onMenuBarUpdate?(nil)
            return
        }
        onMenuBarUpdate?("\(temp)°C")
    }
}
