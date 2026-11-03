import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import Combine

// MARK: - Mouse Chord State Tracking (Session-safe)
private let mouseChordWindow: TimeInterval = 0.12
private let replayedMouseEventTag: Int64 = 0x4D4D4348
private var pendingMouseDown: (type: CGEventType, event: CGEvent, time: TimeInterval)?
private var mouseChordGeneration = 0
private var isLeftMouseDown = false
private var isRightMouseDown = false
private var chordTriggered = false
private var didLogScrollEvent = false
private var didLogMouseEvent = false

// Fast lock-free flags for eventTapCallback
public var gIsMouseChordEnabled: Bool = true
public var gIsAltTabEnabled: Bool = true
public var gIsAltTabVisible: Bool = false
public var gIsClipboardEnabled: Bool = true
public var gIsClipboardHUDVisible: Bool = false
public var gIsClipboardSearchEmpty: Bool = true
private var gActiveModifierMask: CGEventFlags? = nil
private var gCurrentTap: CFMachPort? = nil

/// Maps macOS virtual keycodes for 1...9 to their 0-based clipboard row index.
private func clipboardQuickPasteIndex(for keyCode: Int64) -> Int? {
    switch keyCode {
    case 18: return 0 // 1
    case 19: return 1 // 2
    case 20: return 2 // 3
    case 21: return 3 // 4
    case 23: return 4 // 5
    case 22: return 5 // 6
    case 26: return 6 // 7
    case 28: return 7 // 8
    case 25: return 8 // 9
    default: return nil
    }
}

private func triggerMissionControl() {
    DispatchQueue.main.async {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.exposelauncher")
            ?? URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                appLog("⚠️ Mouse Chord: không mở được Mission Control: \(error.localizedDescription)")
            } else {
                appLog("🖱️ Mouse Chord: đã yêu cầu mở Mission Control.")
            }
        }
    }
}

private func replayMouseEvent(_ event: CGEvent) {
    event.setIntegerValueField(.eventSourceUserData, value: replayedMouseEventTag)
    event.post(tap: .cghidEventTap)
}

private func flushPendingMouseDown() {
    guard let pending = pendingMouseDown else { return }
    pendingMouseDown = nil
    mouseChordGeneration += 1
    replayMouseEvent(pending.event)
}

// MARK: - Event Tap Callback (Session level, zero main-sync)

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // 1. Safety handler for system tap disable
    if type == .tapDisabledByUserInput {
        // User revoked permission in System Settings -> STOP cleanly! Do NOT fight WindowServer!
        appLog("⚠️ EventTap was disabled by user/system in Accessibility settings. Stopping.")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                KeyInterceptor.shared.stop()
            }
        }
        return Unmanaged.passRetained(event)
    }

    if type == .tapDisabledByTimeout {
        // Timeout from macOS -> Re-enable safely
        if let tap = gCurrentTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    if event.getIntegerValueField(.eventSourceUserData) == replayedMouseEventTag {
        return Unmanaged.passRetained(event)
    }

    // Log the first wheel event once so input-tap issues are diagnosable without
    // flooding the runtime log.
    if type == .scrollWheel && !didLogScrollEvent {
        didLogScrollEvent = true
        let nativeEvent = NSEvent(cgEvent: event)
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let isPrecise = nativeEvent?.hasPreciseScrollingDeltas ?? false
        let phase = nativeEvent?.phase.rawValue ?? 0
        let momentum = nativeEvent?.momentumPhase.rawValue ?? 0
        DispatchQueue.global(qos: .utility).async {
            appLog("🖱️ Scroll input received: continuous=\(isContinuous), precise=\(isPrecise), phase=\(phase), momentum=\(momentum)")
        }
    }

    // 2. Handle external wheel scrolling.
    if type == .scrollWheel && SmoothScrollEngine.shared.intercept(event) {
        return nil
    }

    // 3. Mouse Chording: briefly hold the first press so a recognized chord
    // does not leave the foreground app with an unmatched mouse down/up.
    if (type == .leftMouseDown || type == .rightMouseDown) && !didLogMouseEvent {
        didLogMouseEvent = true
        let isEnabled = gIsMouseChordEnabled
        DispatchQueue.global(qos: .utility).async {
            appLog("🖱️ Mouse button input received; Mouse Chord enabled=\(isEnabled).")
        }
    }
    switch type {
    case .leftMouseDown, .rightMouseDown:
        if chordTriggered { return nil }
        guard gIsMouseChordEnabled else {
            flushPendingMouseDown()
            break
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let pending = pendingMouseDown {
            if pending.type != type && now - pending.time <= mouseChordWindow {
                pendingMouseDown = nil
                mouseChordGeneration += 1
                isLeftMouseDown = true
                isRightMouseDown = true
                chordTriggered = true
                DispatchQueue.global(qos: .utility).async {
                    appLog("🖱️ Đã nhận tổ hợp hai nút chuột; mở Mission Control.")
                }
                triggerMissionControl()
                return nil
            }
            flushPendingMouseDown()
        }
        if let delayedEvent = event.copy() {
            pendingMouseDown = (type, delayedEvent, now)
            mouseChordGeneration += 1
            let generation = mouseChordGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + mouseChordWindow) {
                if generation == mouseChordGeneration {
                    flushPendingMouseDown()
                }
            }
            return nil
        }

    case .leftMouseUp, .rightMouseUp:
        if chordTriggered {
            if type == .leftMouseUp { isLeftMouseDown = false }
            if type == .rightMouseUp { isRightMouseDown = false }
            if !isLeftMouseDown && !isRightMouseDown { chordTriggered = false }
            return nil
        }
        if let pending = pendingMouseDown,
           (pending.type == .leftMouseDown && type == .leftMouseUp ||
            pending.type == .rightMouseDown && type == .rightMouseUp) {
            flushPendingMouseDown()
            replayMouseEvent(event)
            return nil
        }

    case .leftMouseDragged, .rightMouseDragged:
        if let pending = pendingMouseDown,
           (pending.type == .leftMouseDown && type == .leftMouseDragged ||
            pending.type == .rightMouseDown && type == .rightMouseDragged) {
            flushPendingMouseDown()
            replayMouseEvent(event)
            return nil
        }

    default:
        break
    }

    // 4. AltTab Window Switching
    if gIsAltTabEnabled {
        if type == .flagsChanged {
            let flags = event.flags
            if let activeMask = gActiveModifierMask {
                if flags.intersection(activeMask) != activeMask {
                    gActiveModifierMask = nil
                    if gIsAltTabVisible {
                        gIsAltTabVisible = false
                        DispatchQueue.main.async {
                            WindowManager.shared.handleModifierReleased()
                        }
                    }
                }
            }
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            let shortcutAction = ShortcutRegistry.action(keyCode: UInt16(keyCode), flags: flags)
            if gIsAltTabEnabled,
               shortcutAction == .altTabNext || shortcutAction == .altTabPrevious {
                let holdMask = flags.intersection([.maskCommand, .maskAlternate, .maskControl])
                gActiveModifierMask = holdMask.isEmpty ? flags.intersection(.maskShift) : holdMask
                let isShift = shortcutAction == .altTabPrevious
                gIsAltTabVisible = true
                DispatchQueue.main.async {
                    WindowManager.shared.handleShortcut(isShift: isShift)
                }
                return nil // Swallow Tab key event so native switcher never triggers
            }

            if let shortcutAction {
                switch shortcutAction {
                case .clipboardHUD where gIsClipboardEnabled:
                    DispatchQueue.main.async { ClipboardManager.shared.toggleHUD() }
                    return nil
                case .snapLeft:
                    DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.leftHalf) }
                    return nil
                case .snapRight:
                    DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.rightHalf) }
                    return nil
                case .snapMaximize:
                    DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.maximize) }
                    return nil
                case .snapCenter:
                    DispatchQueue.main.async { WindowSnapManager.shared.snapActiveWindow(.center) }
                    return nil
                case .moveNextDisplay:
                    DispatchQueue.main.async { WindowSnapManager.shared.moveActiveWindowToDisplay(isNext: true) }
                    return nil
                case .movePreviousDisplay:
                    DispatchQueue.main.async { WindowSnapManager.shared.moveActiveWindowToDisplay(isNext: false) }
                    return nil
                case .toggleMouseChord:
                    DispatchQueue.main.async {
                        ShortcutManager.shared.isMouseChordEnabled.toggle()
                    }
                    return nil
                case .altTabNext, .altTabPrevious, .clipboardHUD:
                    break
                }
            }

            // Keyboard navigation when AltTab HUD is active
            if gIsAltTabVisible {
                if keyCode == 53 { // Esc
                    gIsAltTabVisible = false
                    gActiveModifierMask = nil
                    DispatchQueue.main.async {
                        WindowManager.shared.cancel()
                    }
                    return nil
                } else if keyCode == 50 { // ` or ~ (Tilde) -> cycle backward
                    DispatchQueue.main.async {
                        WindowManager.shared.selectPrevious()
                    }
                    return nil
                } else if keyCode == 123 { // Left Arrow
                    DispatchQueue.main.async {
                        WindowManager.shared.selectPrevious()
                    }
                    return nil
                } else if keyCode == 124 { // Right Arrow
                    DispatchQueue.main.async {
                        WindowManager.shared.selectNext()
                    }
                    return nil
                } else if keyCode == 13 { // W key (Close window)
                    DispatchQueue.main.async {
                        WindowManager.shared.closeSelectedWindow()
                    }
                    return nil
                } else if keyCode == 12 { // Q key (Quit app)
                    DispatchQueue.main.async {
                        WindowManager.shared.quitSelectedApp()
                    }
                    return nil
                }
            }
        }
    }

    // 5. Clipboard HUD and keyboard navigation
    if type == .keyDown {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Clipboard HUD Active Keys
        if gIsClipboardHUDVisible {
            let hasCommand = flags.contains(.maskCommand)
            let hasControl = flags.contains(.maskControl)
            let hasOption = flags.contains(.maskAlternate)

            // Let system-level shortcuts (⌘C, ⌘V, ⌘A...) pass through untouched.
            if !hasCommand && !hasControl {
                if keycode == 53 { // Esc -> Close HUD
                    gIsClipboardHUDVisible = false
                    DispatchQueue.main.async {
                        ClipboardManager.shared.hideHUD()
                    }
                    return nil
                } else if keycode == 126 { // Up Arrow -> previous clip
                    DispatchQueue.main.async {
                        ClipboardManager.shared.selectPrevious()
                    }
                    return nil
                } else if keycode == 125 { // Down Arrow -> next clip
                    DispatchQueue.main.async {
                        ClipboardManager.shared.selectNext()
                    }
                    return nil
                } else if keycode == 36 || keycode == 76 { // Return / Numpad Enter -> paste selection
                    DispatchQueue.main.async {
                        ClipboardManager.shared.pasteSelectedItem()
                    }
                    return nil
                } else if hasOption && keycode == 35 { // ⌥P -> pin / unpin selection
                    DispatchQueue.main.async {
                        ClipboardManager.shared.togglePinSelected()
                    }
                    return nil
                } else if hasOption && (keycode == 51 || keycode == 117) { // ⌥⌫ -> delete selection
                    DispatchQueue.main.async {
                        ClipboardManager.shared.deleteSelectedItem()
                    }
                    return nil
                } else if !hasOption && !flags.contains(.maskShift) && gIsClipboardSearchEmpty,
                          let index = clipboardQuickPasteIndex(for: keycode) { // 1...9 -> instant paste
                    DispatchQueue.main.async {
                        ClipboardManager.shared.pasteItemAt(index: index)
                    }
                    return nil
                }
            }
        }

    }

    return Unmanaged.passRetained(event)
}

// MARK: - KeyInterceptor Singleton

@MainActor
public class KeyInterceptor: ObservableObject {
    public static let shared = KeyInterceptor()

    @Published public private(set) var hasAccessibility = AXIsProcessTrusted()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    public var currentTap: CFMachPort? {
        return eventTap
    }

    private init() {}

    public func updateSettings() {
        gIsAltTabEnabled = (UserDefaults.standard.object(forKey: "alttab_enabled") as? Bool) ?? true
        gIsClipboardEnabled = (UserDefaults.standard.object(forKey: "clipboard_monitoring_enabled") as? Bool) ?? true
    }

    public func start() {
        guard eventTap == nil else { return }

        guard AXIsProcessTrusted() else {
            hasAccessibility = false
            appLog("⚠️ KeyInterceptor: Accessibility chưa được cấp; global scroll và Mouse Chord chưa hoạt động.")
            startPermissionMonitoring()
            return
        }
        hasAccessibility = true
        permissionTimer?.invalidate()
        permissionTimer = nil
        updateSettings()

        // Listen for keybindings, modifier release, mouse chords, and wheel events.
        let eventTypes: [CGEventType] = [
            .keyDown, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .scrollWheel
        ]
        let mask = eventTypes.reduce(UInt64(0)) { $0 | (1 << $1.rawValue) }

        // EXCLUSIVELY use .cgSessionEventTap for user-session safety!
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: nil
        )

        guard let validTap = tap else {
            appLog("⚠️ KeyInterceptor: không tạo được session CGEventTap dù Accessibility đã được cấp.")
            return
        }

        self.eventTap = validTap
        gCurrentTap = validTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, validTap, 0)
        self.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: validTap, enable: true)
        appLog("✅ KeyInterceptor: Active on Session level (Safe, no deadlocks).")
    }

    public func stop() {
        SmoothScrollEngine.shared.stopMotion()
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
            gCurrentTap = nil
            appLog("⏹ KeyInterceptor stopped.")
        }
    }

    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPermissionMonitoring()
    }

    private func startPermissionMonitoring() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAccessibilityPermission()
            }
        }
    }

    private func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        hasAccessibility = trusted
        guard trusted else { return }
        permissionTimer?.invalidate()
        permissionTimer = nil
        if eventTap == nil {
            start()
        }
    }
}
