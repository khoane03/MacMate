import SwiftUI

struct MacMateHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("MacMate")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("Cửa sổ · Clipboard · Chuột")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Thoát MacMate")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct MacMateCardStyle: ViewModifier {
    var padding: CGFloat = 12
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let strokeColor = tint.map { $0.opacity(0.3) } ?? Color.primary.opacity(0.08)
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
}

extension View {
    func macMateCard(padding: CGFloat = 12, tint: Color? = nil) -> some View {
        modifier(MacMateCardStyle(padding: padding, tint: tint))
    }
}
