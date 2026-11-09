import SwiftUI
import AppKit

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // UI preview window (chỉ dùng khi kiểm thử giao diện, không ảnh hưởng người dùng)
        if ProcessInfo.processInfo.environment["MACMATE_PREVIEW"] == "1" {
            showPreviewWindow()
            return
        }

        // Initialize Popover
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 380, height: 570)
        pop.behavior = .transient
        let hostingController = NSHostingController(rootView: MainView())
        hostingController.sizingOptions = []
        pop.contentViewController = hostingController
        self.popover = pop

        // Initialize Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                button.image = image
            } else {
                appLog("Unable to load MenuBarIcon asset")
            }
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Start global shortcuts and the external mouse-wheel engine.
        _ = SmoothScrollManager.shared
        _ = ShortcutManager.shared
        KeyInterceptor.shared.start()

        // Eagerly initialize Clipboard Manager
        _ = ClipboardManager.shared
    }

    func applicationWillTerminate(_ notification: Notification) {
        SmoothScrollManager.shared.stopMotion()
        KeyInterceptor.shared.stop()
        if popover != nil {
            ClipboardManager.shared.flushPendingSave()
        }
    }

    /// Cửa sổ xem trước UI khi đặt `MACMATE_PREVIEW=1` (dùng để chụp/kiểm tra layout).
    /// `MACMATE_PREVIEW_OUT=/path.png` render thẳng ra PNG (không cần quyền chụp màn hình).
    private func showPreviewWindow() {
        let view = MainView()
            .frame(width: 380, height: 570)

        if let out = ProcessInfo.processInfo.environment["MACMATE_PREVIEW_OUT"], !out.isEmpty {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out))
            }
            NSApp.terminate(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 570),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacMate UI Preview"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// MARK: - App Main

@main
@MainActor
enum MacMateMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
