import AppKit
import Combine
import CoreGraphics
import Foundation

/// User-facing settings for mouse-wheel smoothing.
/// The rendering engine intentionally lives off the main actor so the animation
/// keeps running even while SwiftUI is updating the menu-bar popover.
@MainActor
final class SmoothScrollManager: ObservableObject {
    static let shared = SmoothScrollManager()

    private enum DefaultsKey {
        static let enabled = "smooth_scroll_enabled"
        static let reverse = "smooth_scroll_reverse"
        static let speed = "smooth_scroll_speed"
        static let smoothness = "smooth_scroll_smoothness"
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isReverseScrollingEnabled: Bool

    /// 0.5x ... 3.0x distance for each physical wheel notch.
    @Published private(set) var speed: Double

    /// 0.0 is responsive, 1.0 has the longest easing/inertia tail.
    @Published private(set) var smoothness: Double

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = (defaults.object(forKey: DefaultsKey.enabled) as? Bool) ?? true
        isReverseScrollingEnabled = defaults.bool(forKey: DefaultsKey.reverse)

        let savedSpeed = defaults.object(forKey: DefaultsKey.speed) as? Double
        speed = min(max(savedSpeed ?? 1.0, 0.5), 3.0)

        let savedSmoothness = defaults.object(forKey: DefaultsKey.smoothness) as? Double
        smoothness = min(max(savedSmoothness ?? 0.62, 0.0), 1.0)

        SmoothScrollEngine.shared.configure(
            enabled: isEnabled,
            reverse: isReverseScrollingEnabled,
            speed: speed,
            smoothness: smoothness
        )
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.enabled)
        applyConfiguration()
    }

    func setReverseScrollingEnabled(_ enabled: Bool) {
        guard enabled != isReverseScrollingEnabled else { return }
        isReverseScrollingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.reverse)
        applyConfiguration()
    }

    func setSpeed(_ value: Double) {
        let clamped = min(max(value, 0.5), 3.0)
        guard clamped != speed else { return }
        speed = clamped
        UserDefaults.standard.set(clamped, forKey: DefaultsKey.speed)
        applyConfiguration()
    }

    func setSmoothness(_ value: Double) {
        let clamped = min(max(value, 0.0), 1.0)
        guard clamped != smoothness else { return }
        smoothness = clamped
        UserDefaults.standard.set(clamped, forKey: DefaultsKey.smoothness)
        applyConfiguration()
    }

    private func applyConfiguration() {
        // This manager is main-actor isolated, so every @Published mutation above
        // is delivered to SwiftUI on the main thread. The engine receives values
        // only and never writes back into the observable model.
        SmoothScrollEngine.shared.configure(
            enabled: isEnabled,
            reverse: isReverseScrollingEnabled,
            speed: speed,
            smoothness: smoothness
        )
    }

    func stopMotion() {
        SmoothScrollEngine.shared.stopMotion()
    }
}

/// Converts discrete external mouse-wheel events into pixel-scroll frames.
/// Trackpad and touch-mouse events always remain under macOS control.
final class SmoothScrollEngine: @unchecked Sendable {
    static let shared = SmoothScrollEngine()

    private static let generatedEventTag: Int64 = 0x4D_41_43_4D_41_54_45 // "MACMATE"
    private static let pixelsPerNotch = 42.0

    private let queue = DispatchQueue(label: "com.macmate.smooth-scroll", qos: .userInteractive)
    private let configurationLock = NSLock()

    private var enabled = true
    private var reverse = false
    private var speed = 1.0
    private var smoothness = 0.62

    // Accessed only by `queue`.
    private var remainingX = 0.0
    private var remainingY = 0.0
    private var fractionalX = 0.0
    private var fractionalY = 0.0
    private var latestFlags: CGEventFlags = []
    private var scrollLocation: CGPoint = .zero
    private var scrollDisplay: CGDirectDisplayID?
    private var eventSource: CGEventSource?
    private var lastFrameTime = ProcessInfo.processInfo.systemUptime
    private var isAnimating = false
    private var animationGeneration: UInt = 0

    private init() {}

    func configure(enabled: Bool, reverse: Bool, speed: Double, smoothness: Double) {
        configurationLock.lock()
        let directionChanged = self.reverse != reverse
        self.enabled = enabled
        self.reverse = reverse
        self.speed = min(max(speed, 0.5), 3.0)
        self.smoothness = min(max(smoothness, 0.0), 1.0)
        configurationLock.unlock()

        if !enabled || directionChanged {
            stopMotion()
        }
    }

    /// Returns true when the original wheel event should be swallowed.
    func intercept(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.generatedEventTag {
            return false
        }

        configurationLock.lock()
        let currentEnabled = enabled
        let currentReverse = reverse
        let currentSpeed = speed
        configurationLock.unlock()

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let nativeEvent = NSEvent(cgEvent: event)
        let isPrecise = nativeEvent?.hasPreciseScrollingDeltas ?? true
        let hasGesturePhase = nativeEvent.map {
            !$0.phase.isEmpty || !$0.momentumPhase.isEmpty
        } ?? false

        // Only handle traditional wheel packets. Some trackpad events can lack
        // phase metadata, so precision and continuity must also be excluded.
        guard !isContinuous, !isPrecise, !hasGesturePhase else { return false }

        if !currentEnabled {
            guard currentReverse else { return false }
            reverseWheelEvent(event)
            return false
        }

        let deltaY: Double
        let deltaX: Double
        if nativeEvent?.hasPreciseScrollingDeltas == true {
            deltaY = Double(nativeEvent?.scrollingDeltaY ?? 0)
            deltaX = Double(nativeEvent?.scrollingDeltaX ?? 0)
        } else {
            deltaY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            deltaX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        }
        guard deltaX != 0 || deltaY != 0 else { return false }

        // Capping one unusually large driver delta avoids a single wheel packet
        // producing seconds of scrolling while retaining acceleration bursts.
        let direction = currentReverse ? -1.0 : 1.0
        let impulseX = min(max(deltaX, -12), 12) * Self.pixelsPerNotch * currentSpeed * direction
        let impulseY = min(max(deltaY, -12), 12) * Self.pixelsPerNotch * currentSpeed * direction
        let flags = event.flags
        let location = event.location
        let display = Self.displayID(at: location)

        queue.async { [weak self] in
            guard let self else { return }
            if self.scrollDisplay != display {
                self.resetMotion()
            }
            self.scrollDisplay = display
            self.scrollLocation = location
            self.remainingX += impulseX
            self.remainingY += impulseY
            self.latestFlags = flags
            self.startAnimationIfNeeded()
        }
        return true
    }

    private func reverseWheelEvent(_ event: CGEvent) {
        for field in [
            CGEventField.scrollWheelEventDeltaAxis1,
            .scrollWheelEventDeltaAxis2,
            .scrollWheelEventPointDeltaAxis1,
            .scrollWheelEventPointDeltaAxis2,
            .scrollWheelEventFixedPtDeltaAxis1,
            .scrollWheelEventFixedPtDeltaAxis2
        ] {
            let value = event.getIntegerValueField(field)
            if value != 0 {
                event.setIntegerValueField(field, value: -value)
            }
        }
    }

    func stopMotion() {
        queue.async { [weak self] in
            self?.resetMotion()
        }
    }

    private func resetMotion() {
        remainingX = 0
        remainingY = 0
        fractionalX = 0
        fractionalY = 0
        scrollDisplay = nil
        isAnimating = false
        animationGeneration &+= 1
        lastFrameTime = ProcessInfo.processInfo.systemUptime
    }

    private static func displayID(at location: CGPoint) -> CGDirectDisplayID? {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        let result = CGGetDisplaysWithPoint(location, 1, &display, &count)
        return result == .success && count > 0 ? display : nil
    }

    private func startAnimationIfNeeded() {
        guard !isAnimating else { return }
        isAnimating = true
        animationGeneration &+= 1
        lastFrameTime = ProcessInfo.processInfo.systemUptime
        scheduleFrame(generation: animationGeneration)
    }

    private func scheduleFrame(generation: UInt) {
        queue.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
            self?.renderFrame(generation: generation)
        }
    }

    private func renderFrame(generation: UInt) {
        guard isAnimating, generation == animationGeneration else { return }
        guard remainingX != 0 || remainingY != 0 else {
            isAnimating = false
            lastFrameTime = ProcessInfo.processInfo.systemUptime
            return
        }

        configurationLock.lock()
        let currentEnabled = enabled
        let currentSmoothness = smoothness
        configurationLock.unlock()
        guard currentEnabled else {
            resetMotion()
            return
        }

        // Stop the tail as soon as the user moves the pointer to work elsewhere.
        // This also prevents pending frames from reaching another display.
        if let pointerLocation = CGEvent(source: nil)?.location {
            let movedAway = abs(pointerLocation.x - scrollLocation.x) > 10 ||
                abs(pointerLocation.y - scrollLocation.y) > 10
            let changedDisplay = scrollDisplay.map {
                !CGDisplayBounds($0).contains(pointerLocation)
            } ?? false
            if movedAway || changedDisplay {
                resetMotion()
                return
            }
        }

        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = min(max(now - lastFrameTime, 1.0 / 240.0), 1.0 / 30.0)
        lastFrameTime = now

        // Exponential convergence makes repeated notches accumulate naturally:
        // the leading edge reacts immediately and the remaining distance eases out.
        let timeConstant = 0.035 + (currentSmoothness * 0.20)
        let easing = 1.0 - exp(-deltaTime / timeConstant)

        var stepX = remainingX * easing
        var stepY = remainingY * easing
        if abs(remainingX) < 0.25 {
            stepX = remainingX
        }
        if abs(remainingY) < 0.25 {
            stepY = remainingY
        }
        remainingX -= stepX
        remainingY -= stepY

        fractionalX += stepX
        fractionalY += stepY
        let emittedX = Int32(fractionalX.rounded(.towardZero))
        let emittedY = Int32(fractionalY.rounded(.towardZero))
        fractionalX -= Double(emittedX)
        fractionalY -= Double(emittedY)

        if emittedX != 0 || emittedY != 0 {
            postPixelScroll(x: emittedX, y: emittedY, flags: latestFlags, location: scrollLocation)
        }
        scheduleFrame(generation: generation)
    }

    private func postPixelScroll(x: Int32, y: Int32, flags: CGEventFlags, location: CGPoint) {
        if eventSource == nil {
            eventSource = CGEventSource(stateID: .privateState)
        }
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: y,
            wheel2: x,
            wheel3: 0
        ) else { return }

        event.flags = flags
        event.location = location
        event.setIntegerValueField(.eventSourceUserData, value: Self.generatedEventTag)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cgSessionEventTap)
    }
}
