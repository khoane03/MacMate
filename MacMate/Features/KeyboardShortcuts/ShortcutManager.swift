import AppKit
import Combine
import Foundation

public enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case altTabNext
    case altTabPrevious
    case clipboardHUD
    case snapLeft
    case snapRight
    case snapMaximize
    case snapCenter
    case moveNextDisplay
    case movePreviousDisplay
    case toggleMouseChord

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .altTabNext: return "Alt-Tab: Chuyển tiếp"
        case .altTabPrevious: return "Alt-Tab: Chuyển lùi"
        case .clipboardHUD: return "Mở Clipboard HUD"
        case .snapLeft: return "Chia cửa sổ: Nửa trái"
        case .snapRight: return "Chia cửa sổ: Nửa phải"
        case .snapMaximize: return "Chia cửa sổ: Phóng to"
        case .snapCenter: return "Chia cửa sổ: Căn giữa"
        case .moveNextDisplay: return "Chuyển cửa sổ sang màn hình kế tiếp"
        case .movePreviousDisplay: return "Chuyển cửa sổ sang màn hình trước"
        case .toggleMouseChord: return "Bật/tắt Mouse Chord"
        }
    }
}

public struct ShortcutBinding: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifierFlags: UInt64
    public var isEnabled: Bool

    public init(keyCode: UInt16, modifierFlags: UInt64, isEnabled: Bool = true) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.isEnabled = isEnabled
    }
}

enum ShortcutRegistry {
    private static let lock = NSLock()
    private static var actionsByChord: [UInt64: ShortcutAction] = [:]
    private static let modifierMask: UInt64 =
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskShift.rawValue

    static func chord(keyCode: UInt16, modifierFlags: UInt64) -> UInt64 {
        (UInt64(keyCode) << 32) | (modifierFlags & modifierMask)
    }

    static func replace(with bindings: [ShortcutAction: ShortcutBinding]) {
        var next: [UInt64: ShortcutAction] = [:]
        for action in ShortcutAction.allCases {
            guard let binding = bindings[action], binding.isEnabled else { continue }
            next[chord(keyCode: binding.keyCode, modifierFlags: binding.modifierFlags)] = action
        }
        lock.lock()
        actionsByChord = next
        lock.unlock()
    }

    static func action(keyCode: UInt16, flags: CGEventFlags) -> ShortcutAction? {
        let key = chord(keyCode: keyCode, modifierFlags: flags.rawValue)
        lock.lock()
        defer { lock.unlock() }
        return actionsByChord[key]
    }

    static func normalizedFlags(_ flags: CGEventFlags) -> UInt64 {
        flags.rawValue & modifierMask
    }
}

@MainActor
public final class ShortcutManager: ObservableObject {
    public static let shared = ShortcutManager()
    private static let defaultsKey = "global_shortcut_bindings"

    @Published public private(set) var bindings: [ShortcutAction: ShortcutBinding] = [:] {
        didSet {
            persist()
            ShortcutRegistry.replace(with: bindings)
        }
    }

    @Published public var isMouseChordEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMouseChordEnabled, forKey: "mouse_chord_enabled")
            gIsMouseChordEnabled = isMouseChordEnabled
        }
    }

    private init() {
        isMouseChordEnabled = (UserDefaults.standard.object(forKey: "mouse_chord_enabled") as? Bool) ?? true
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) {
            bindings = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, binding in
                guard let action = ShortcutAction(rawValue: key) else { return nil }
                return (action, binding)
            })
        }
        for (action, binding) in Self.defaultBindings where bindings[action] == nil {
            bindings[action] = binding
        }
        ShortcutRegistry.replace(with: bindings)
        gIsMouseChordEnabled = isMouseChordEnabled
    }

    public func binding(for action: ShortcutAction) -> ShortcutBinding {
        bindings[action] ?? Self.defaultBindings[action]!
    }

    public func setBinding(_ binding: ShortcutBinding, for action: ShortcutAction) -> Bool {
        guard binding.isEnabled else {
            bindings[action] = binding
            return true
        }
        let normalized = ShortcutRegistry.normalizedFlags(CGEventFlags(rawValue: binding.modifierFlags))
        let candidate = ShortcutBinding(
            keyCode: binding.keyCode,
            modifierFlags: normalized,
            isEnabled: true
        )
        let hasConflict = bindings.contains { otherAction, otherBinding in
            otherAction != action &&
                otherBinding.isEnabled &&
                otherBinding.keyCode == candidate.keyCode &&
                ShortcutRegistry.normalizedFlags(CGEventFlags(rawValue: otherBinding.modifierFlags)) == candidate.modifierFlags
        }
        guard !hasConflict else { return false }
        bindings[action] = candidate
        return true
    }

    public func restoreDefaults() {
        bindings = Self.defaultBindings
    }

    private func persist() {
        let encoded = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encoded) else {
            appLog("⚠️ ShortcutManager: không thể mã hóa cấu hình phím tắt.")
            return
        }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static let defaultBindings: [ShortcutAction: ShortcutBinding] = [
        .altTabNext: ShortcutBinding(keyCode: 48, modifierFlags: CGEventFlags.maskCommand.rawValue),
        .altTabPrevious: ShortcutBinding(keyCode: 48, modifierFlags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue),
        .clipboardHUD: ShortcutBinding(keyCode: 8, modifierFlags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue),
        .snapLeft: ShortcutBinding(keyCode: 123, modifierFlags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue),
        .snapRight: ShortcutBinding(keyCode: 124, modifierFlags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue),
        .snapMaximize: ShortcutBinding(keyCode: 126, modifierFlags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue),
        .snapCenter: ShortcutBinding(keyCode: 125, modifierFlags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue),
        .moveNextDisplay: ShortcutBinding(keyCode: 124, modifierFlags: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue),
        .movePreviousDisplay: ShortcutBinding(keyCode: 123, modifierFlags: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue),
        .toggleMouseChord: ShortcutBinding(keyCode: 46, modifierFlags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue, isEnabled: false)
    ]
}

enum ShortcutKeyLabel {
    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↵",
        37: "L", 38: "J", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        51: "⌫", 53: "Esc", 115: "Home", 116: "Page Up", 117: "Forward Delete",
        119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func text(for binding: ShortcutBinding) -> String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: binding.modifierFlags)
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }

        parts.append(keyNames[binding.keyCode] ?? "Key \(binding.keyCode)")
        return parts.joined()
    }
}
