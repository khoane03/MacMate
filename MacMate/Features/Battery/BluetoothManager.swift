import Foundation
import AppKit

// MARK: - Bluetooth Manager (Native IOBluetooth Dynamic Bridge)

public final class BluetoothManager {
    public static let shared = BluetoothManager()

    private typealias GetPowerStateFunc = @convention(c) () -> Int32
    private typealias SetPowerStateFunc = @convention(c) (Int32) -> Int32

    private var getPowerState: GetPowerStateFunc?
    private var setPowerState: SetPowerStateFunc?
    private var isLoaded: Bool = false
    private let bluetoothUsageDescriptionPresent =
        Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil

    private init() {
        loadFramework()
    }

    private func loadFramework() {
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY) else {
            return
        }
        if let symGet = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") {
            getPowerState = unsafeBitCast(symGet, to: GetPowerStateFunc.self)
        }
        if let symSet = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") {
            setPowerState = unsafeBitCast(symSet, to: SetPowerStateFunc.self)
        }
        isLoaded = (getPowerState != nil && setPowerState != nil)
    }

    public var isAvailable: Bool {
        (isLoaded && bluetoothUsageDescriptionPresent) || blueutilPath != nil
    }

    public var isPowerOn: Bool {
        get {
            if isLoaded, bluetoothUsageDescriptionPresent, let getPower = getPowerState {
                return getPower() != 0
            }
            guard let (_, output, status) = runBlueutil(arguments: ["--power"]),
                  status == 0,
                  let value = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return true
            }
            return value != 0
        }
        set {
            if isLoaded, bluetoothUsageDescriptionPresent, let setPower = setPowerState,
               setPower(newValue ? 1 : 0) == 0 {
                return
            }
            guard blueutilPath != nil else {
                appLog("⚠️ Sleep Guard: Bluetooth không đổi được — IOBluetooth bị từ chối và blueutil chưa được cài.")
                return
            }
            DispatchQueue.global(qos: .utility).async {
                guard let (_, _, status) = self.runBlueutil(arguments: ["--power", newValue ? "1" : "0"]),
                      status == 0 else {
                    appLog("⚠️ Sleep Guard: blueutil không thể đổi trạng thái Bluetooth.")
                    return
                }
            }
        }
    }

    private var blueutilPath: URL? {
        [
            "/opt/homebrew/bin/blueutil",
            "/usr/local/bin/blueutil"
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func runBlueutil(arguments: [String]) -> (Process, String, Int32)? {
        guard let executable = blueutilPath else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process, String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
        } catch {
            appLog("⚠️ Sleep Guard: không chạy được blueutil: \(error.localizedDescription)")
            return nil
        }
    }
}
