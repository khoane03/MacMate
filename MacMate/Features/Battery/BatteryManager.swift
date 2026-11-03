import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import Combine
import AppKit

// IOPM.h defines this as a macro that Swift cannot import from the SDK.
private let batteryStatusChangedMessage: natural_t = 0xE002_4100

private func batteryPowerManagementCallback(
    _ refcon: UnsafeMutableRawPointer?,
    _ service: io_service_t,
    _ messageType: natural_t,
    _ messageArgument: UnsafeMutableRawPointer?
) {
    guard messageType == batteryStatusChangedMessage else { return }
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            BatteryManager.shared.handleBatteryStatusChanged()
        }
    }
}

// MARK: - Battery Manager (Hardware Care & Longevity)

@MainActor
public class BatteryManager: ObservableObject {
    public static let shared = BatteryManager()

    // MARK: - Published State
    @Published public var currentLevel: Int = 0
    @Published public var maxCapacityPercent: Int = 100
    @Published public var maxCapacity: Int = 0
    @Published public var nominalCapacity: Int = 0
    @Published public var designCapacity: Int = 0
    @Published public var healthPercent: Int = 100
    @Published public var exactHealthPercent: Double = 100.0
    @Published public var cycleCount: Int = 0
    @Published public var temperature: Double = 0.0      // in °C
    @Published public var voltage: Double = 0.0          // in Volts
    @Published public var amperage: Int = 0              // in mA
    @Published public var wattage: Double = 0.0          // in Watts
    @Published public var isPluggedIn: Bool = false
    @Published public var isCharging: Bool = false
    @Published public var isFullyCharged: Bool = false
    @Published public var timeRemaining: Int = 0         // in minutes
    @Published public var isBypassActive: Bool = false    // SMC CHTE = 1 (Running direct from AC)
    @Published public var isHelperInstalled: Bool = false
    @Published public var isInstallingHelper: Bool = false
    @Published public var statusMessage: String = "Đang kiểm tra..."
    @Published public var lastUpdated: Date = Date()

    // Extended Telemetry
    @Published public var adapterWatts: Int = 0          // e.g. 30W
    @Published public var adapterDescription: String = "" // e.g. "pd charger"
    @Published public var adapterSerial: String = ""
    @Published public var batterySerial: String = ""
    @Published public var gasGaugeChip: String = ""

    // User Settings (Stored in UserDefaults)
    @Published public var isProtectionEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isProtectionEnabled, forKey: "battery_protection_enabled")
            evaluatePowerManagement()
        }
    }

    @Published public var chargeLimit: Int = 80 {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: "battery_charge_limit")
            evaluatePowerManagement()
        }
    }

    @Published public var isTopUpActive: Bool = false {
        didSet {
            UserDefaults.standard.set(isTopUpActive, forKey: "battery_top_up_active")
            evaluatePowerManagement()
        }
    }

    @Published public var isTempAlertEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isTempAlertEnabled, forKey: "battery_temp_alert_enabled")
        }
    }

    @Published public var isSmartAlertsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSmartAlertsEnabled, forKey: "battery_smart_alerts_enabled")
        }
    }

    // Hardware Tab Selection (0: Nguồn & Pin, 1: Sleep Guard, 2: Đóng băng CPU, 3: Hiệu chuẩn)
    @Published public var selectedHardwareTab: Int = 0

    // Sleep Guard Settings & State
    @Published public var isSleepGuardEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSleepGuardEnabled, forKey: "battery_sleep_guard_enabled")
        }
    }

    @Published public var sleepGuardTurnOffBluetooth: Bool = true {
        didSet {
            UserDefaults.standard.set(sleepGuardTurnOffBluetooth, forKey: "battery_sleep_guard_bt")
        }
    }

    @Published public var lastSleepReport: String = ""

    private var sleepDate: Date? = nil
    private var sleepBatteryLevel: Int = 0
    private var wasBypassActiveAtSleep = false
    private var wasBluetoothTurnedOffBySleepGuard: Bool = false

    // Calibration State Machine
    public enum CalibrationState: String, CaseIterable {
        case idle = "idle"
        case discharging = "discharging"
        case charging = "charging"
        case resting = "resting"
        case completed = "completed"
    }

    @Published public var calibrationState: CalibrationState = .idle
    @Published public var calibrationMessage: String = ""
    private var restingTimer: Timer?

    // Auto-Scheduled Calibration
    @Published public var isAutoCalibrationEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isAutoCalibrationEnabled, forKey: "battery_auto_calibration_enabled")
        }
    }

    @Published public var calibrationIntervalDays: Int = 30 {
        didSet {
            UserDefaults.standard.set(calibrationIntervalDays, forKey: "battery_calibration_interval_days")
        }
    }

    @Published public var lastCalibrationDate: Date? = nil {
        didSet {
            if let date = lastCalibrationDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "battery_last_calibration_timestamp")
            }
        }
    }

    public var nextScheduledCalibrationDate: Date {
        let base = lastCalibrationDate ?? Date()
        return Calendar.current.date(byAdding: .day, value: calibrationIntervalDays, to: base) ?? Date()
    }

    public var daysRemainingUntilCalibration: Int {
        let now = Date()
        let next = nextScheduledCalibrationDate
        let diff = Calendar.current.dateComponents([.day], from: now, to: next).day ?? 0
        return max(0, diff)
    }

    public var tempAlertThreshold: Double = 38.0 // Warning at 38°C
    private var lastTempAlertDate: Date? = nil
    private var lastLowBatteryAlertLevel: Int? = nil
    private var hasAlertedBypassThisSession: Bool = false

    private var powerManagementRootPort: io_connect_t = 0
    private var powerNotificationPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    private var batteryPollTimer: Timer?
    private var isPopoverVisible = false

    private init() {
        // Load preferences
        if UserDefaults.standard.object(forKey: "battery_protection_enabled") != nil {
            self.isProtectionEnabled = UserDefaults.standard.bool(forKey: "battery_protection_enabled")
        } else {
            self.isProtectionEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_temp_alert_enabled") != nil {
            self.isTempAlertEnabled = UserDefaults.standard.bool(forKey: "battery_temp_alert_enabled")
        } else {
            self.isTempAlertEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_smart_alerts_enabled") != nil {
            self.isSmartAlertsEnabled = UserDefaults.standard.bool(forKey: "battery_smart_alerts_enabled")
        } else {
            self.isSmartAlertsEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_sleep_guard_enabled") != nil {
            self.isSleepGuardEnabled = UserDefaults.standard.bool(forKey: "battery_sleep_guard_enabled")
        } else {
            self.isSleepGuardEnabled = true
        }

        if UserDefaults.standard.object(forKey: "battery_sleep_guard_bt") != nil {
            self.sleepGuardTurnOffBluetooth = UserDefaults.standard.bool(forKey: "battery_sleep_guard_bt")
        } else {
            self.sleepGuardTurnOffBluetooth = true
        }

        self.lastSleepReport = UserDefaults.standard.string(forKey: "battery_last_sleep_report") ?? ""

        let savedLimit = UserDefaults.standard.integer(forKey: "battery_charge_limit")
        if savedLimit >= 50 && savedLimit <= 100 {
            self.chargeLimit = savedLimit
        } else {
            self.chargeLimit = 80
        }

        self.isTopUpActive = UserDefaults.standard.bool(forKey: "battery_top_up_active")

        if UserDefaults.standard.object(forKey: "battery_auto_calibration_enabled") != nil {
            self.isAutoCalibrationEnabled = UserDefaults.standard.bool(forKey: "battery_auto_calibration_enabled")
        } else {
            self.isAutoCalibrationEnabled = true
        }

        let savedInterval = UserDefaults.standard.integer(forKey: "battery_calibration_interval_days")
        if savedInterval >= 15 && savedInterval <= 120 {
            self.calibrationIntervalDays = savedInterval
        } else {
            self.calibrationIntervalDays = 30
        }

        let lastCalTimestamp = UserDefaults.standard.double(forKey: "battery_last_calibration_timestamp")
        if lastCalTimestamp > 0 {
            self.lastCalibrationDate = Date(timeIntervalSince1970: lastCalTimestamp)
        } else {
            let now = Date()
            self.lastCalibrationDate = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "battery_last_calibration_timestamp")
        }

        // Setup Sleep Observers
        setupSleepObservers()

        // Initial check
        checkHelperStatus()
        refreshBatteryInfo()
        checkSMCBypassStatus()
        evaluatePowerManagement()

        registerBatteryNotifications()
    }

    deinit {
        restingTimer?.invalidate()
        batteryPollTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if powerNotifier != 0 {
            IODeregisterForSystemPower(&powerNotifier)
        }
        if powerManagementRootPort != 0 {
            IOServiceClose(powerManagementRootPort)
        }
        if let powerNotificationPort {
            IONotificationPortDestroy(powerNotificationPort)
        }
    }

    // MARK: - Sleep Guard Lifecycle

    private func setupSleepObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWillSleep(_ notification: Notification) {
        guard isSleepGuardEnabled else { return }
        refreshBatteryInfo()
        self.sleepDate = Date()
        self.sleepBatteryLevel = self.currentLevel

        // Turn off Bluetooth if configured to prevent phantom Dark Wake drain
        if sleepGuardTurnOffBluetooth && BluetoothManager.shared.isAvailable && BluetoothManager.shared.isPowerOn {
            self.wasBluetoothTurnedOffBySleepGuard = true
            BluetoothManager.shared.isPowerOn = false
        }

        // Hard lock SMC CHTE to 1 if at or above limit to prevent waking or sleep-charging overrides
        if isProtectionEnabled && currentLevel >= chargeLimit && isHelperInstalled {
            let (_, status) = shell("sudo -n /usr/local/bin/displaycontrol-power charge-off \(chargeLimit)")
            self.wasBypassActiveAtSleep = status == 0
        } else {
            self.wasBypassActiveAtSleep = self.isBypassActive
        }
    }

    @objc private func handleDidWake(_ notification: Notification) {
        guard isSleepGuardEnabled else { return }

        refreshBatteryInfo()

        // Restore Bluetooth if previously turned off by Sleep Guard
        if wasBluetoothTurnedOffBySleepGuard && BluetoothManager.shared.isAvailable {
            BluetoothManager.shared.isPowerOn = true
            wasBluetoothTurnedOffBySleepGuard = false
        }

        // Re-enforce the SMC limit after reading the actual post-wake charge.
        evaluatePowerManagement()

        // Calculate sleep duration & battery delta
        if let sDate = sleepDate {
            let elapsed = Date().timeIntervalSince(sDate)
            let hours = Int(elapsed) / 3600
            let mins = (Int(elapsed) % 3600) / 60
            let drain = max(0, sleepBatteryLevel - currentLevel)
            let drainText = "Hao pin: \(drain)% (\(sleepBatteryLevel)% → \(currentLevel)%)"
            let smcText = wasBypassActiveAtSleep ? "SMC đã khóa sạc" : "SMC không khóa sạc"
            let report = "Ngủ \(hours)h\(mins)m • \(drainText) • \(smcText)"
            self.lastSleepReport = report
            UserDefaults.standard.set(report, forKey: "battery_last_sleep_report")

            if isSmartAlertsEnabled {
                sendNotification(
                    title: "🛡️ Sleep Guard: Báo cáo khi mở máy",
                    body: "Máy đã nghỉ \(hours)h\(mins)m. \(drainText). \(smcText)."
                )
            }
            self.sleepDate = nil
        }
    }

    private func registerBatteryNotifications() {
        powerManagementRootPort = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &powerNotificationPort,
            batteryPowerManagementCallback,
            &powerNotifier
        )
        guard powerManagementRootPort != 0,
              let powerNotificationPort,
              let source = IONotificationPortGetRunLoopSource(powerNotificationPort)?.takeUnretainedValue() else {
            appLog("⚠️ BatteryManager: không đăng ký được IOKit battery notifications.")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    public func handleBatteryStatusChanged() {
        refreshBatteryInfo()
        checkSMCBypassStatus()
        checkAutoCalibrationSchedule()
        evaluatePowerManagement()
    }

    public func setPopoverVisible(_ visible: Bool) {
        guard isPopoverVisible != visible else { return }
        isPopoverVisible = visible
        if visible {
            refreshBatteryInfo()
            batteryPollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshBatteryInfo()
                }
            }
        } else {
            batteryPollTimer?.invalidate()
            batteryPollTimer = nil
        }
    }

    // MARK: - IOKit Battery Status Query

    public func refreshBatteryInfo() {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            return
        }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return
        }

        let currentCapacity = dict["CurrentCapacity"] as? Int
        let maxCapacity = dict["MaxCapacity"] as? Int
        self.nominalCapacity = dict["NominalChargeCapacity"] as? Int ?? self.nominalCapacity
        self.maxCapacity = maxCapacity ?? self.nominalCapacity
        self.designCapacity = dict["DesignCapacity"] as? Int ?? self.designCapacity
        let batteryData = dict["BatteryData"] as? [String: Any]
        let stateOfCharge = (batteryData?["UISoc"] as? NSNumber)?.intValue
            ?? (dict["UISoc"] as? NSNumber)?.intValue
        let systemLevel = systemBatteryLevel()
        let calculatedLevel: Int? = {
            guard let currentCapacity, let maxCapacity, maxCapacity > 0 else { return nil }
            return Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
        }()
        self.currentLevel = min(100, max(0, stateOfCharge ?? systemLevel ?? calculatedLevel ?? self.currentLevel))
        self.maxCapacityPercent = 100
        self.cycleCount = dict["CycleCount"] as? Int ?? self.cycleCount
        self.isCharging = dict["IsCharging"] as? Bool ?? false
        self.isPluggedIn = dict["ExternalConnected"] as? Bool ?? false
        self.isFullyCharged = dict["FullyCharged"] as? Bool ?? false
        self.timeRemaining = dict["TimeRemaining"] as? Int ?? 0

        if let rawTemp = dict["Temperature"] as? Double {
            self.temperature = rawTemp / 100.0
        } else if let rawTempInt = dict["Temperature"] as? Int {
            self.temperature = Double(rawTempInt) / 100.0
        }

        if let rawVolt = dict["Voltage"] as? Double {
            self.voltage = rawVolt / 1000.0
        } else if let rawVoltInt = dict["Voltage"] as? Int {
            self.voltage = Double(rawVoltInt) / 1000.0
        }

        if let rawAmp = dict["Amperage"] as? NSNumber {
            // Signed 64-bit: negative = discharging, positive = charging, 0 = bypass
            self.amperage = rawAmp.intValue
        }

        // Live Wattage = Voltage (V) * abs(Amperage (A))
        self.wattage = (self.voltage * Double(abs(self.amperage))) / 1000.0

        // Parse Adapter details
        if let adapter = dict["AdapterDetails"] as? [String: Any] {
            self.adapterWatts = adapter["Watts"] as? Int ?? self.adapterWatts
            self.adapterDescription = adapter["Description"] as? String ?? self.adapterDescription
            self.adapterSerial = adapter["SerialString"] as? String ?? self.adapterSerial
        } else if let adapterList = dict["AppleRawAdapterDetails"] as? [[String: Any]], let first = adapterList.first {
            self.adapterWatts = first["Watts"] as? Int ?? self.adapterWatts
            self.adapterDescription = first["Description"] as? String ?? self.adapterDescription
            self.adapterSerial = first["SerialString"] as? String ?? self.adapterSerial
        }

        self.batterySerial = dict["Serial"] as? String ?? self.batterySerial
        self.gasGaugeChip = dict["DeviceName"] as? String ?? self.gasGaugeChip

        let fullChargeCapacity = self.maxCapacity
        if self.designCapacity > 0 && fullChargeCapacity > 0 {
            let ratio = Double(fullChargeCapacity) / Double(self.designCapacity) * 100.0
            self.exactHealthPercent = ratio
            self.healthPercent = min(100, Int(round(ratio)))
        }

        self.lastUpdated = Date()
        checkTemperatureAlert()
        checkSmartSafetyAlerts()
    }

    private func systemBatteryLevel() -> Int? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue()
        for index in 0..<CFArrayGetCount(sources) {
            let source = unsafeBitCast(CFArrayGetValueAtIndex(sources, index), to: CFTypeRef.self)
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType as String,
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int else { continue }
            let maximum = description[kIOPSMaxCapacityKey as String] as? Int
            let level: Int
            if let maximum, maximum > 0, (current > 100 || maximum > 100) {
                level = Int((Double(current) / Double(maximum) * 100).rounded())
            } else {
                level = current
            }
            return min(100, max(0, level))
        }
        return nil
    }

    // MARK: - Smart Safety & Anti-Wear Alerts

    private func checkSmartSafetyAlerts() {
        guard isSmartAlertsEnabled else { return }

        // Alert: Low battery warning to prevent deep discharge (<20% and <10%)
        if !isPluggedIn {
            if currentLevel <= 10 {
                if lastLowBatteryAlertLevel != 10 {
                    lastLowBatteryAlertLevel = 10
                    sendNotification(
                        title: "🚨 KHẨN CẤP: Pin còn 10%!",
                        body: "Tuyệt đối không để máy dùng cạn đáy sập nguồn (gây hại cell pin vĩnh viễn). Hãy cắm sạc ngay!"
                    )
                }
            } else if currentLevel <= 20 {
                if lastLowBatteryAlertLevel != 20 {
                    lastLowBatteryAlertLevel = 20
                    sendNotification(
                        title: "⚠️ Pin yếu (20%) - Hãy cắm sạc!",
                        body: "Để tránh hiện tượng tụt áp sâu (Deep Discharge) làm chai pin, hãy cắm sạc ngay bây giờ."
                    )
                }
            } else {
                lastLowBatteryAlertLevel = nil
            }
        } else {
            lastLowBatteryAlertLevel = nil
        }

        // 3. Informational Alert: Reached limit with AC Bypass active
        if isPluggedIn && isBypassActive && currentLevel >= chargeLimit {
            if !hasAlertedBypassThisSession {
                hasAlertedBypassThisSession = true
                sendNotification(
                    title: "🛡️ Đã khóa \(chargeLimit)% - Chuyển sang nguồn AC trực tiếp",
                    body: "Pin đã được ngắt sạc an toàn. MacBook đang dùng điện trực tiếp từ củ sạc để chống chai pin tối đa!"
                )
            }
        } else if !isPluggedIn || currentLevel < (chargeLimit - 4) {
            hasAlertedBypassThisSession = false
        }
    }

    // MARK: - Temperature Safety Alerts

    private func checkTemperatureAlert() {
        guard isTempAlertEnabled && temperature >= tempAlertThreshold else { return }

        let now = Date()
        if let last = lastTempAlertDate, now.timeIntervalSince(last) < 600 {
            return // Wait at least 10 minutes between alerts
        }
        lastTempAlertDate = now

        let tempStr = String(format: "%.1f°C", temperature)
        sendNotification(
            title: "⚠️ Cảnh báo nhiệt độ pin (\(tempStr))",
            body: "Nhiệt độ pin MacBook đã lên tới \(tempStr)! Hãy kê thoáng máy hoặc mở phần Giám sát năng lượng để đóng băng các tác vụ nặng."
        )
    }

    private func sendNotification(title: String, body: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\" sound name \"Submarine\""
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    public func checkSMCBypassStatus() {
        guard isHelperInstalled else { return }
        DispatchQueue.global(qos: .utility).async {
            let (out, code) = shell("sudo -n /usr/local/bin/displaycontrol-power status")
            DispatchQueue.main.async {
                if code == 0 {
                    let isBypassed: Bool
                    if out.contains("CHTE") {
                        isBypassed = out.contains("01 00 00 00") || out.contains("bytes 01 00 00 00")
                    } else if out.contains("BCLM"),
                              let byteText = out.range(of: #"(?i)bytes\s+([0-9a-f]{2})"#, options: .regularExpression).map({ String(out[$0]).split(separator: " ").last }),
                              let byteText,
                              let value = Int(byteText, radix: 16) {
                        isBypassed = value < 100
                    } else {
                        isBypassed = false
                    }
                    self.isBypassActive = isBypassed
                } else {
                    appLog("⚠️ BatteryManager: không đọc được trạng thái SMC (mã \(code)): \(out)")
                }
            }
        }
    }

    // MARK: - Power & Limiter Evaluation

    public func evaluatePowerManagement() {
        guard isHelperInstalled else {
            statusMessage = "Cần cấp quyền để kích hoạt bảo vệ nguồn SMC"
            return
        }

        // 1. Calibration State handling
        if calibrationState != .idle {
            switch calibrationState {
            case .discharging:
                if currentLevel <= 20 {
                    calibrationState = .charging
                    calibrationMessage = "Bước 2/3: Sạc đầy 100% để cân bằng cell (Hiện tại: \(currentLevel)%)"
                    setChargingInhibited(false)
                    sendNotification(
                        title: "⚡️ Hiệu chuẩn pin: Đã đạt 20%",
                        body: isPluggedIn
                            ? "Đang sạc liên tục lên 100% để cân bằng điện áp các cell pin."
                            : "Hãy cắm sạc để MacMate sạc cân bằng cell lên 100% và tự động khóa lại ở 80%."
                    )
                } else {
                    setChargingInhibited(true)
                    if isPluggedIn {
                        calibrationMessage = "Bước 1/3: Rút sạc dùng máy xuống 20% (Hiện tại: \(currentLevel)%)"
                    } else {
                        calibrationMessage = "Bước 1/3: Đang dùng pin xuống 20% (Hiện tại: \(currentLevel)%)"
                    }
                }
                return

            case .charging:
                if currentLevel >= 100 {
                    calibrationState = .resting
                    calibrationMessage = "Bước 3/3: Giữ 100% trong 15 phút để ổn định hóa chất cell..."
                    setChargingInhibited(false)
                    sendNotification(
                        title: "🔋 Hiệu chuẩn pin: Đạt 100%",
                        body: "Đang giữ 100% trong 15 phút để các cell pin cân bằng hoàn toàn."
                    )
                    restingTimer?.invalidate()
                    restingTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: false) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.completeCalibration()
                        }
                    }
                } else {
                    setChargingInhibited(false)
                    calibrationMessage = "Bước 2/3: Đang sạc lên 100% (Hiện tại: \(currentLevel)%)"
                }
                return

            case .resting:
                return

            case .completed, .idle:
                break
            }
        }

        // 2. Normal power state
        if !isPluggedIn {
            statusMessage = "Đang dùng pin (\(currentLevel)%)"
            return
        }

        // Plugged in
        if isTopUpActive {
            setChargingInhibited(false)
            if currentLevel >= 100 {
                isTopUpActive = false
                statusMessage = "Đã sạc đầy 100%"
            } else {
                statusMessage = "⚡️ Đang sạc đầy tạm thời (\(currentLevel)%)"
            }
            return
        }

        if isProtectionEnabled {
            if currentLevel >= chargeLimit {
                setChargingInhibited(true)
                statusMessage = "🛡️ Nguồn AC trực tiếp (Đã khóa \(chargeLimit)% chống chai pin)"
            } else if currentLevel <= max(10, chargeLimit - 3) {
                setChargingInhibited(false)
                statusMessage = "⚡️ Đang sạc bù lên \(chargeLimit)% (\(currentLevel)%)"
            } else {
                if isBypassActive {
                    statusMessage = "🛡️ Nguồn AC trực tiếp (\(currentLevel)%)"
                } else {
                    statusMessage = "⚡️ Đang sạc (\(currentLevel)%)"
                }
            }
        } else {
            setChargingInhibited(false)
            statusMessage = isFullyCharged ? "Đã sạc đầy 100%" : "Đang sạc thường (\(currentLevel)%)"
        }
    }

    // MARK: - SMC Charging Inhibit Control

    public func setChargingInhibited(_ inhibit: Bool) {
        guard isHelperInstalled else { return }
        let action = inhibit ? "charge-off \(chargeLimit)" : "charge-on"
        DispatchQueue.global(qos: .utility).async {
            let (_, code) = shell("sudo -n /usr/local/bin/displaycontrol-power \(action)")
            DispatchQueue.main.async {
                if code == 0 {
                    self.isBypassActive = inhibit
                }
            }
        }
    }

    // MARK: - Battery Calibration API & Auto-Scheduler

    public func checkAutoCalibrationSchedule() {
        guard isAutoCalibrationEnabled && calibrationState == .idle && isHelperInstalled else { return }
        guard let last = lastCalibrationDate else {
            lastCalibrationDate = Date()
            return
        }

        let now = Date()
        let daysPassed = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0

        if daysPassed >= calibrationIntervalDays {
            // Reached schedule!
            if currentLevel <= 25 && isPluggedIn {
                // Pin đã thấp sẵn và đang cắm sạc -> chuyển thẳng sang Bước 2 sạc cân bằng
                calibrationState = .charging
                calibrationMessage = "Bước 2/3: Đang sạc lên 100% để cân bằng cell (Hiện tại: \(currentLevel)%)"
                setChargingInhibited(false)
                sendNotification(
                    title: "⚡️ Bắt đầu hiệu chuẩn pin tự động",
                    body: "Pin đang ở mức \(currentLevel)%. MacMate đang sạc lên 100% để cân bằng cell và sẽ tự động khóa lại ở 80%."
                )
            } else if calibrationState == .idle {
                startCalibration(isAutomatic: true)
            }
        }
    }

    public func startCalibration(isAutomatic: Bool = false) {
        guard isHelperInstalled else {
            statusMessage = "Cần cấp quyền SMC để hiệu chuẩn pin"
            return
        }

        if currentLevel <= 22 {
            // Pin đã thấp sẵn -> bắt đầu sạc cân bằng ngay
            calibrationState = .charging
            calibrationMessage = "Bước 2/3: Đang sạc lên 100% để cân bằng cell (Hiện tại: \(currentLevel)%)"
            setChargingInhibited(false)
            sendNotification(
                title: "⚡️ Hiệu chuẩn pin: Bắt đầu sạc cân bằng cell",
                body: "Pin đang ở mức \(currentLevel)%. Đang nạp đầy 100% để cân bằng vi sai điện áp các cell."
            )
            return
        }

        calibrationState = .discharging
        if isPluggedIn {
            calibrationMessage = "Bước 1/3: Rút sạc dùng máy xuống 20% (Hiện tại: \(currentLevel)%)"
        } else {
            calibrationMessage = "Bước 1/3: Đang dùng pin xuống 20% (Hiện tại: \(currentLevel)%)"
        }
        setChargingInhibited(true)

        let reason = isAutomatic ? "Tự động theo lịch \(calibrationIntervalDays) ngày" : "Thủ công"
        sendNotification(
            title: "🔬 Bắt đầu hiệu chuẩn pin (\(reason))",
            body: isPluggedIn
                ? "Bước 1: Rút sạc dùng máy tự nhiên xuống mức 20%. Sau đó cắm sạc lại để MacMate tự động làm phần còn lại."
                : "Bước 1: Tiếp tục dùng pin xuống mức 20%. Sau đó cắm sạc lại để MacMate tự động làm phần còn lại."
        )
    }

    public func cancelCalibration() {
        calibrationState = .idle
        calibrationMessage = ""
        restingTimer?.invalidate()
        restingTimer = nil
        evaluatePowerManagement()
    }

    private func completeCalibration() {
        calibrationState = .completed
        self.lastCalibrationDate = Date()
        calibrationMessage = "🎉 Hiệu chuẩn hoàn tất! Lịch tiếp theo sau \(calibrationIntervalDays) ngày."
        setChargingInhibited(true)
        sendNotification(
            title: "🎉 Hiệu chuẩn pin thành công!",
            body: "Dung lượng cell đã được cân bằng chính xác. Chế độ nguồn AC trực tiếp đã được tự động khóa lại ở \(chargeLimit)%."
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.calibrationState == .completed {
                self?.calibrationState = .idle
                self?.calibrationMessage = ""
                self?.evaluatePowerManagement()
            }
        }
    }

    // MARK: - Helper Installation Check & Prompt

    public func checkHelperStatus() {
        let exists = FileManager.default.fileExists(atPath: "/usr/local/bin/displaycontrol-power")
        if !exists {
            self.isHelperInstalled = false
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let (_, code) = shell("sudo -n /usr/local/bin/displaycontrol-power status")
            DispatchQueue.main.async {
                self.isHelperInstalled = (code == 0)
            }
        }
    }

    public func installHelper(completion: ((Bool) -> Void)? = nil) {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true

        DispatchQueue.global(qos: .userInitiated).async {
            let smcSrc = Bundle.main.path(forResource: "smc", ofType: nil)
            let helperSrc = Bundle.main.path(forResource: "displaycontrol-power", ofType: nil)
            let installScript = Bundle.main.path(forResource: "install-helper", ofType: "sh")

            guard let sSMC = smcSrc, let sHelper = helperSrc, let sInstall = installScript else {
                DispatchQueue.main.async {
                    self.isInstallingHelper = false
                    completion?(false)
                }
                return
            }

            let privilegedCommand = ["/bin/bash", sInstall, sSMC, sHelper]
                .map(Self.shellQuoted)
                .joined(separator: " ")
            let appleScriptCommand = privilegedCommand
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let appleScriptCmd = "do shell script \"\(appleScriptCommand)\" with administrator privileges"

            var errorDict: NSDictionary?
            if let scriptObj = NSAppleScript(source: appleScriptCmd) {
                _ = scriptObj.executeAndReturnError(&errorDict)
            }

            // Verify installation
            let (_, code) = shell("sudo -n /usr/local/bin/displaycontrol-power status")
            let success = (code == 0)

            DispatchQueue.main.async {
                self.isInstallingHelper = false
                self.isHelperInstalled = success
                if success {
                    self.evaluatePowerManagement()
                }
                completion?(success)
            }
        }
    }

    private nonisolated static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
