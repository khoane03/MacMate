import SwiftUI

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text("Open Source • Miễn phí")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Update Check / Action Button
            Button {
                updateManager.checkForUpdates(silent: false)
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: updateManager.hasNewUpdate ? "sparkles" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                    Text(updateManager.hasNewUpdate ? "Có bản v\(updateManager.latestVersionString)" : "Kiểm tra cập nhật")
                        .font(.system(size: 10, weight: updateManager.hasNewUpdate ? .bold : .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(updateManager.hasNewUpdate ? Color.green.opacity(0.14) : Color.primary.opacity(0.06)))
                .foregroundStyle(updateManager.hasNewUpdate ? Color.green : Color.primary)
            }
            .buttonStyle(.plain)
            .help(updateManager.hasNewUpdate ? "Đã có bản mới! Bấm để cập nhật" : "Kiểm tra phiên bản mới từ GitHub")

           Button {
                NSApplication.shared.terminate(nil)
           } label: {
                 Label("Thoát", systemImage: "power")
            }
           .font(.system(size: 10))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }
}

// MARK: - In-App Update Modal View

struct UpdateModalView: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        ZStack {
            // Dimmed semi-transparent backdrop
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    if case .downloading = updateManager.state {
                        // Prevent closing during download
                    } else if case .extracting = updateManager.state {
                        // Prevent closing
                    } else {
                        updateManager.showUpdateModal = false
                    }
                }

            // Modal Dialog Card
            VStack(spacing: 12) {
                // Header Bar
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Cập nhật MacMate")
                                .font(.system(size: 12, weight: .bold))
                            Text("Phiên bản hiện tại: v\(UpdateManager.currentVersion)")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        updateManager.showUpdateModal = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // State Content
                switch updateManager.state {
                case .idle, .checking:
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Đang kiểm tra bản cập nhật mới trên GitHub...")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .upToDate(let ver):
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)

                        Text("Bạn đang dùng phiên bản mới nhất!")
                            .font(.system(size: 11.5, weight: .semibold))

                        Text("MacMate v\(ver) hiện là phiên bản cập nhật nhất. Máy của bạn đã sẵn sàng.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)

                        Button {
                            updateManager.checkForUpdates(silent: false)
                        } label: {
                            Text("Kiểm tra lại")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .updateAvailable(let ver, let notes, _, _):
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.cyan)

                            Text("Đã có phiên bản mới: v\(ver)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.cyan)
                        }

                        // Release Notes Box
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Điểm mới trong bản v\(ver):")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ScrollView(.vertical, showsIndicators: true) {
                                Text(notes)
                                    .font(.system(size: 9))
                                    .lineSpacing(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                            .frame(height: 95)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }

                        // Action Buttons
                        VStack(spacing: 6) {
                            Button {
                                updateManager.startUpdate()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Cập nhật ngay (Tự động tải & Cài đặt)")
                                        .font(.system(size: 10.5, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.accentColor)
                                )
                                .foregroundStyle(Color.white)
                            }
                            .buttonStyle(.plain)

                            Button {
                                updateManager.openReleasePage()
                            } label: {
                                Text("Xem chi tiết trên GitHub")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)

                case .downloading(let progress):
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.app.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentColor)

                        Text("Đang tải bản cập nhật: \(Int(progress * 100))%")
                            .font(.system(size: 11.5, weight: .semibold))

                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .padding(.horizontal, 20)

                        Text("MacMate sẽ tự động thay thế và khởi động lại ngay sau khi tải xong.")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .extracting, .readyToRestart:
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)

                        Text("Đang cài đặt & chuẩn bị khởi động lại...")
                            .font(.system(size: 11, weight: .semibold))

                        Text("Ứng dụng sẽ tự động mở lại trong giây lát.")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)

                case .failed(let errorMsg):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.orange)

                        Text("Không thể cập nhật tự động")
                            .font(.system(size: 11, weight: .semibold))

                        Text(errorMsg)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)

                        HStack(spacing: 8) {
                            Button {
                                updateManager.checkForUpdates(silent: false)
                            } label: {
                                Text("Thử lại")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)

                            Button {
                                updateManager.openReleasePage()
                            } label: {
                                Text("Mở GitHub Releases")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                }

                Divider()

                // Preferences Row: Auto check on launch
                HStack {
                    Text("Tự động kiểm tra bản mới khi mở MacMate")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Toggle("", isOn: Binding<Bool>(
                        get: { updateManager.autoCheckEnabled },
                        set: { updateManager.autoCheckEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
    }
}
