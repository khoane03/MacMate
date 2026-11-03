import AppKit
import SwiftUI

public struct KeyRecorderView: View {
    let binding: ShortcutBinding
    let onRecord: (ShortcutBinding) -> Bool
    @State private var isRecording = false
    @State private var hasConflict = false

    public init(binding: ShortcutBinding, onRecord: @escaping (ShortcutBinding) -> Bool) {
        self.binding = binding
        self.onRecord = onRecord
    }

    public var body: some View {
        Group {
            if isRecording {
                ShortcutCaptureField { captured in
                    hasConflict = !onRecord(captured)
                    if !hasConflict { isRecording = false }
                } onCancel: {
                    isRecording = false
                }
                .frame(width: 104, height: 24)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.5)))
            } else {
                Button(ShortcutKeyLabel.text(for: binding)) {
                    hasConflict = false
                    isRecording = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(width: 104)
            }
        }
        .help(hasConflict ? "Tổ hợp phím này đã được dùng" : "Bấm để ghi tổ hợp phím mới")
        .overlay(alignment: .bottomTrailing) {
            if hasConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .offset(x: 4, y: 4)
            }
        }
    }
}

private struct ShortcutCaptureField: NSViewRepresentable {
    let onRecord: (ShortcutBinding) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onRecord = onRecord
        nsView.onCancel = onCancel
        if nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }

    final class CaptureView: NSView {
        var onRecord: ((ShortcutBinding) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func draw(_ dirtyRect: NSRect) {
            let text = "Ấn tổ hợp phím…"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onCancel?()
                return
            }
            let flags = ShortcutRegistryFlags.normalized(event.modifierFlags)
            guard flags != 0 else { return }
            onRecord?(ShortcutBinding(
                keyCode: event.keyCode,
                modifierFlags: flags,
                isEnabled: true
            ))
        }
    }
}

private enum ShortcutRegistryFlags {
    static func normalized(_ flags: NSEvent.ModifierFlags) -> UInt64 {
        var value: UInt64 = 0
        if flags.contains(.command) { value |= CGEventFlags.maskCommand.rawValue }
        if flags.contains(.option) { value |= CGEventFlags.maskAlternate.rawValue }
        if flags.contains(.control) { value |= CGEventFlags.maskControl.rawValue }
        if flags.contains(.shift) { value |= CGEventFlags.maskShift.rawValue }
        return value
    }
}
