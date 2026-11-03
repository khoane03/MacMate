import SwiftUI

// MARK: - TAB 0: Hardware Care, Battery & Thermal View

struct HardwareCareTabView: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var thermalManager: ThermalManager = ThermalManager.shared
    @ObservedObject private var energyManager = ProcessEnergyManager.shared

    var body: some View {
        VStack(spacing: 6) {
            // Segment Switcher: Battery and thermal details
            HStack(spacing: 4) {
                sectionButton(
                    index: 0,
                    title: "Pin & Nguồn",
                    icon: "bolt.shield.fill"
                )
                sectionButton(
                    index: 1,
                    title: "Nhiệt độ & Cảm biến",
                    icon: "thermometer.sun.fill",
                    badge: thermalManager.cpuAvgTemp > 0 ? String(format: "%.0f°C", thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp) : nil
                )
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.055)))
            .padding(.horizontal, 14)
            .padding(.top, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if thermalManager.selectedSection == 0 {
                        BatteryCardView(batteryManager: batteryManager, onSelectThermalSection: {
                            thermalManager.selectedSection = 1
                        })
                    } else {
                        ThermalCardView(thermalManager: thermalManager)
                    }
                }
                .onAppear {
                    updateProcessMonitoring()
                }
                .onDisappear {
                    energyManager.setProcessSectionVisible(false)
                }
                .onChange(of: batteryManager.selectedHardwareTab) { _, _ in
                    updateProcessMonitoring()
                }
                .onChange(of: thermalManager.selectedSection) { _, _ in
                    updateProcessMonitoring()
                    if thermalManager.selectedSection == 1 {
                        thermalManager.refreshMetrics()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private func updateProcessMonitoring() {
        energyManager.setProcessSectionVisible(
            thermalManager.selectedSection == 0 && batteryManager.selectedHardwareTab == 2
        )
    }

    private func sectionButton(index: Int, title: String, icon: String, badge: String? = nil) -> some View {
        Button {
            thermalManager.selectedSection = index
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: thermalManager.selectedSection == index ? .bold : .medium))

                if let badge = badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(thermalManager.selectedSection == index ? Color.white.opacity(0.25) : Color.primary.opacity(0.08)))
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(thermalManager.selectedSection == index ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(thermalManager.selectedSection == index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Battery Protection Card View (Hallmark-Disciplined & Un-Clipped)

struct BatteryCardView: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var energyManager: ProcessEnergyManager = ProcessEnergyManager.shared
    var onSelectThermalSection: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main Battery Level Bar + Target Limit Notch + Live Wattage
            VStack(spacing: 4) {
                HStack(alignment: .lastTextBaseline) {
                    HStack(spacing: 2) {
                        Text("\(batteryManager.currentLevel)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Live Wattage
                    if batteryManager.isBypassActive {
                        Text("🛡️ 0.0W (Nguồn AC trực tiếp)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.cyan)
                    } else if batteryManager.isCharging {
                        Text(String(format: "⚡️ +%.1fW (Đang sạc)", batteryManager.wattage))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    } else if batteryManager.isPluggedIn {
                        Text("🔌 0.0W (Đã cắm sạc)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    } else {
                        let mins = batteryManager.timeRemaining
                        let timeStr = mins > 0 ? " • Còn ~\(mins / 60)h\(mins % 60)m" : ""
                        Text(String(format: "🔋 -%.1fW%@", batteryManager.wattage, timeStr))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                // Custom Progress Bar with Lock Notch
                GeometryReader { geo in
                    let width = geo.size.width
                    let levelFraction = min(1.0, max(0.0, Double(batteryManager.currentLevel) / 100.0))
                    let limitFraction = min(1.0, max(0.0, Double(batteryManager.chargeLimit) / 100.0))

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: batteryManager.isBypassActive
                                        ? [Color.cyan, Color.blue]
                                        : [Color.green, Color.mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, width * levelFraction), height: 8)

                        if batteryManager.isProtectionEnabled {
                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: 2.5, height: 12)
                                .offset(x: max(0, width * limitFraction - 1.25), y: 0)
                        }
                    }
                }
                .frame(height: 12)

                if batteryManager.isProtectionEnabled {
                    HStack {
                        Spacer()
                        Text("Ngưỡng khóa: \(batteryManager.chargeLimit)%")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            }

            // 4 Hardware Health & Telemetry Metrics (Clean 4-column row)
            HStack(spacing: 5) {
                metricChip(
                    icon: "heart.fill",
                    iconColor: .pink,
                    title: "Độ khỏe cell",
                    val: String(format: "%.1f%%", batteryManager.exactHealthPercent),
                    sub: "\(batteryManager.maxCapacity)/\(batteryManager.designCapacity) mAh"
                )
                metricChip(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .purple,
                    title: "Chu kỳ sạc",
                    val: "\(batteryManager.cycleCount) lần",
                    sub: "Thiết kế: 1000"
                )
                Button {
                    onSelectThermalSection?()
                } label: {
                    metricChip(
                        icon: "thermometer.medium",
                        iconColor: tempBadgeColor,
                        title: "Nhiệt độ pin",
                        val: String(format: "%.1f°C", batteryManager.temperature),
                        sub: tempStatusText + " ›",
                        valColor: tempBadgeColor
                    )
                }
                .buttonStyle(.plain)
                .help("Bấm để xem nhiệt độ và cảm biến")

                metricChip(
                    icon: "bolt.fill",
                    iconColor: .yellow,
                    title: "Củ sạc",
                    val: batteryManager.adapterWatts > 0 ? "\(batteryManager.adapterWatts)W" : "Dùng Pin",
                    sub: batteryManager.adapterWatts > 0
                        ? (batteryManager.adapterDescription.isEmpty ? "Đang kết nối" : batteryManager.adapterDescription)
                        : "Không kết nối"
                )
            }

            HStack(spacing: 5) {
                metricChip(
                    icon: "arrow.left.arrow.right",
                    iconColor: .cyan,
                    title: "Dòng điện",
                    val: "\(batteryManager.amperage) mA",
                    sub: batteryManager.amperage < 0 ? "Đang xả" : "Đang nạp"
                )
                metricChip(
                    icon: "bolt",
                    iconColor: .orange,
                    title: "Điện áp",
                    val: String(format: "%.2f V", batteryManager.voltage),
                    sub: "Pin hiện tại"
                )
                metricChip(
                    icon: "bolt.fill",
                    iconColor: .yellow,
                    title: "Công suất",
                    val: String(format: "%.1f W", batteryManager.wattage),
                    sub: "Ước tính thực"
                )
            }

            // High-Temperature Alert Banner
            if batteryManager.temperature >= batteryManager.tempAlertThreshold {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cảnh báo: Pin đang ấm (\(String(format: "%.1f°C", batteryManager.temperature)))!")
                            .font(.system(size: 9.5, weight: .bold)).foregroundStyle(.red)
                        Text("Kiểm tra mục Đóng băng để tạm dừng các tiến trình nền sử dụng nhiều CPU.")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.1)))
            }

            // Sub-Navigation Pills (4 Tabs: Nguồn SMC, Sleep Guard, Đóng băng CPU, Lịch hiệu chuẩn)
            HStack(spacing: 3) {
                subTabButton(index: 0, title: "Nguồn SMC", icon: "bolt.shield")
                subTabButton(index: 1, title: "Sleep Guard", icon: "moon.stars")
                subTabButton(index: 2, title: "Đóng băng", icon: "snowflake")
                subTabButton(index: 3, title: "Lịch hiệu chuẩn", icon: "calendar.badge.clock")
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))

            // Sub-Tab Content
            switch batteryManager.selectedHardwareTab {
            case 0:
                powerOverviewSubTab
            case 1:
                sleepGuardSubTab
            case 2:
                processFreezeSubTab
            case 3:
                autoScheduledCalibrationSubTab
            default:
                powerOverviewSubTab
            }
        }
        .macMateCard(padding: 12, tint: batteryManager.isBypassActive ? .cyan : nil)
    }

    private func metricChip(icon: String, iconColor: Color, title: String, val: String, sub: String, valColor: Color = .primary) -> some View {
        VStack(spacing: 1.5) {
            HStack(spacing: 2.5) {
                Image(systemName: icon).font(.system(size: 8.5)).foregroundStyle(iconColor)
                Text(title).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(val).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(valColor)
            Text(sub).font(.system(size: 7.5)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    private func subTabButton(index: Int, title: String, icon: String) -> some View {
        Button {
            batteryManager.selectedHardwareTab = index
            if index == 2 {
                energyManager.refreshProcesses()
            }
        } label: {
            HStack(spacing: 2.5) {
                Image(systemName: icon).font(.system(size: 9))
                Text(title).font(.system(size: 9, weight: batteryManager.selectedHardwareTab == index ? .bold : .medium))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(batteryManager.selectedHardwareTab == index ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(batteryManager.selectedHardwareTab == index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // SUB-TAB 0: NGUỒN SMC
    private var powerOverviewSubTab: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield").font(.system(size: 11)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Khóa sạc ở \(batteryManager.chargeLimit)% (Chạy điện trực tiếp)")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Cắm sạc liên tục không chai pin (SMC Bypass)")
                        .font(.system(size: 7.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding<Bool>(
                    get: { batteryManager.isProtectionEnabled },
                    set: { batteryManager.isProtectionEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            if batteryManager.isProtectionEnabled {
                HStack(spacing: 6) {
                    Text("Mức khóa:")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach([70, 80, 90], id: \.self) { val in
                        Button {
                            batteryManager.chargeLimit = val
                        } label: {
                            Text("\(val)%\(val == 80 ? " (Chuẩn)" : "")")
                                .font(.system(size: 8, weight: batteryManager.chargeLimit == val ? .bold : .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(batteryManager.chargeLimit == val ? Color.accentColor : Color.primary.opacity(0.06)))
                                .foregroundStyle(batteryManager.chargeLimit == val ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Button {
                    batteryManager.isTopUpActive.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: batteryManager.isTopUpActive ? "xmark.circle" : "bolt.fill")
                            .font(.system(size: 8))
                        Text(batteryManager.isTopUpActive ? "Hủy sạc 100% (Khóa lại)" : "⚡️ Sạc đầy 100% tạm thời")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(batteryManager.isTopUpActive ? Color.orange.opacity(0.18) : Color.primary.opacity(0.06))
                    .foregroundStyle(batteryManager.isTopUpActive ? Color.orange : Color.primary)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Khi cần mang máy ra ngoài").font(.system(size: 7.5)).foregroundStyle(.tertiary)
            }

            // Toggles
            toggleRow(icon: "thermometer.sun.fill", iconColor: .orange, title: "Thông báo khi pin nóng > 38°C", isOn: Binding<Bool>(
                get: { batteryManager.isTempAlertEnabled },
                set: { batteryManager.isTempAlertEnabled = $0 }
            ))
            toggleRow(icon: "bell.badge.fill", iconColor: .blue, title: "Cảnh báo chống chai pin (Màn ngoài, pin < 20%)", isOn: Binding<Bool>(
                get: { batteryManager.isSmartAlertsEnabled },
                set: { batteryManager.isSmartAlertsEnabled = $0 }
            ))
        }
    }

    // SUB-TAB 1: SLEEP GUARD
    private var sleepGuardSubTab: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "moon.fill").font(.system(size: 11)).foregroundStyle(Color.purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bảo vệ Sleep Guard khi gập máy")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Chống Dark Wake và ngăn máy nóng ngầm trong balo")
                        .font(.system(size: 7.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding<Bool>(
                    get: { batteryManager.isSleepGuardEnabled },
                    set: { batteryManager.isSleepGuardEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            if batteryManager.isSleepGuardEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "wave.3.forward.circle.fill").font(.system(size: 10)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tự ngắt Bluetooth khi gập máy")
                            .font(.system(size: 9, weight: .medium))
                        Text("AirPods/chuột không đánh thức máy ngầm qua đêm. Tự bật lại ngay khi mở máy.")
                            .font(.system(size: 7.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding<Bool>(
                        get: { batteryManager.sleepGuardTurnOffBluetooth },
                        set: { batteryManager.sleepGuardTurnOffBluetooth = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))

                HStack(spacing: 5) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 8.5)).foregroundStyle(.green)
                    Text("Khóa SMC 80% được bảo lưu liên tục trong lúc ngủ và tái kích hoạt ngay khi mở màn hình.")
                        .font(.system(size: 7.8)).foregroundStyle(.secondary)
                }

                if !batteryManager.lastSleepReport.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 8)).foregroundStyle(.purple)
                        Text("Lần gần nhất: \(batteryManager.lastSleepReport)")
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(.purple)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.purple.opacity(0.08)))
                }
            }
        }
    }

    // SUB-TAB 2: PROCESS FREEZE
    private var processFreezeSubTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tiến trình ngốn CPU & Tỏa nhiệt:")
                    .font(.system(size: 9.5, weight: .semibold))
                Spacer()
                Button {
                    energyManager.refreshProcesses()
                } label: {
                    HStack(spacing: 2.5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 7.5))
                        Text("Quét lại").font(.system(size: 8))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            if energyManager.processes.isEmpty {
                HStack {
                    Spacer()
                    Text("Máy đang rất mát mẻ, không có tiến trình nền nặng.")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 3.5) {
                    ForEach(energyManager.processes) { p in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(p.isFrozen ? Color.cyan : (p.cpu > 25.0 ? Color.red : Color.orange))
                                .frame(width: 5, height: 5)

                            VStack(alignment: .leading, spacing: 0.5) {
                                Text(p.name)
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .lineLimit(1)
                                Text("PID: \(p.pid)")
                                    .font(.system(size: 6.8)).foregroundStyle(.tertiary)
                            }

                            Spacer()

                            if p.isFrozen {
                                Text("❄️ ĐÃ ĐÓNG BĂNG")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.cyan.opacity(0.12)))
                            } else {
                                Text(String(format: "%.1f%% CPU", p.cpu))
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundStyle(p.cpu > 25.0 ? Color.red : Color.orange)
                            }

                            Button {
                                if p.isFrozen {
                                    energyManager.resumeProcess(pid: p.pid)
                                } else {
                                    energyManager.freezeProcess(pid: p.pid)
                                }
                            } label: {
                                Text(p.isFrozen ? "▶️ Rã đông" : "❄️ Đóng băng")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(p.isFrozen ? Color.green.opacity(0.15) : Color.cyan.opacity(0.15))
                                    .foregroundStyle(p.isFrozen ? Color.green : Color.cyan)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.03)))
                    }
                }
            }

            Text("💡 Đóng băng (SIGSTOP) giữ nguyên cửa sổ và dữ liệu trong RAM nhưng ngừng 100% việc đốt CPU và tỏa nhiệt trên M2.")
                .font(.system(size: 7.2)).foregroundStyle(.secondary)
        }
    }

    // SUB-TAB 3: AUTO-SCHEDULED BATTERY CALIBRATION (BMS)
    private var autoScheduledCalibrationSubTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Master Auto-Schedule Toggle
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Tự động đặt lịch hiệu chuẩn pin định kỳ")
                        .font(.system(size: 10, weight: .bold))
                    Text("Cân bằng điện áp cell & khôi phục thước đo dung lượng chuẩn")
                        .font(.system(size: 7.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding<Bool>(
                    get: { batteryManager.isAutoCalibrationEnabled },
                    set: { batteryManager.isAutoCalibrationEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            if batteryManager.isAutoCalibrationEnabled {
                // Interval Selector Pills
                HStack(spacing: 5) {
                    Text("Chu kỳ:")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)

                    ForEach([30, 45, 60], id: \.self) { days in
                        Button {
                            batteryManager.calibrationIntervalDays = days
                        } label: {
                            Text("Mỗi \(days) ngày\(days == 30 ? " (Chuẩn)" : "")")
                                .font(.system(size: 7.5, weight: batteryManager.calibrationIntervalDays == days ? .bold : .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(batteryManager.calibrationIntervalDays == days ? Color.accentColor : Color.primary.opacity(0.06))
                                )
                                .foregroundStyle(batteryManager.calibrationIntervalDays == days ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }

                // Schedule Info Box
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 8)).foregroundStyle(.orange)
                        Text("Lịch tiếp theo:")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(formatDate(batteryManager.nextScheduledCalibrationDate))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("Còn \(batteryManager.daysRemainingUntilCalibration) ngày")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                    }

                    HStack {
                        Image(systemName: "checkmark.circle").font(.system(size: 8)).foregroundStyle(.green)
                        Text("Lần gần nhất:")
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(batteryManager.lastCalibrationDate != nil ? formatDate(batteryManager.lastCalibrationDate!) : "Chưa thực hiện")
                            .font(.system(size: 7.5))
                            .foregroundStyle(.secondary)
                    }

                    Text("💡 Quy trình: Khi đến lịch, bạn rút sạc dùng máy tự nhiên xuống ≤ 20%. Khi cắm sạc lại, MacMate sẽ tự động sạc 100% cân bằng cell ➔ ngâm 15p ➔ tự khóa lại 80% SMC Bypass.")
                        .font(.system(size: 7.2))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
            }

            // Action: Manual Run or Active Status
            if batteryManager.calibrationState == .idle {
                Button {
                    batteryManager.startCalibration()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "play.circle.fill").font(.system(size: 8.5))
                        Text("Hiệu chuẩn ngay bây giờ (Chạy trước lịch)")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 4) {
                    HStack {
                        ProgressView().controlSize(.mini)
                        Text(batteryManager.calibrationMessage)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.1)))

                    Button {
                        batteryManager.cancelCalibration()
                    } label: {
                        Text("Hủy hiệu chuẩn (Quay về khóa 80%)")
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggleRow(icon: String, iconColor: Color, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 8.5)).foregroundStyle(iconColor)
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }

    private var tempBadgeColor: Color {
        if batteryManager.temperature < 32.0 {
            return .green
        } else if batteryManager.temperature < 38.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var tempStatusText: String {
        if batteryManager.temperature < 32.0 {
            return "Mát mẻ"
        } else if batteryManager.temperature < 38.0 {
            return "Ấm nhẹ"
        } else {
            return "Nóng!"
        }
    }
}


// MARK: - Thermal Sensor View

/* Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V5 */
struct ThermalCardView: View {
    @ObservedObject var thermalManager: ThermalManager

    var body: some View {
        VStack(spacing: 8) {
            // 1. Device Profile & Thermal Health Header
            deviceHeaderCard

            // 2. Optional Menu Bar temperature pill
            menuBarMonitorRow

            // 3. Temperature Sensor Matrix
            thermalMatrixGrid

            // 4. Detailed Sensor Breakdown (Expandable Accordion)
            detailedSensorsAccordion
        }
    }

    // MARK: - 1. Device Header Card
    private var deviceHeaderCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(headerIconBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(headerIconColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(thermalManager.machineModelName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)

                        Text(thermalManager.isIntelMac ? "SMC Intel" : "HID PMU")
                            .font(.system(size: 8, weight: .heavy))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .foregroundStyle(.secondary)
                    }

                    Text("Cảm biến nhiệt \(thermalManager.isIntelMac ? "Intel" : "Apple Silicon") • Cập nhật mỗi 2.5s")
                        .font(.system(size: 7.8))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Thermal State Pill
                HStack(spacing: 3) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 5, height: 5)
                    Text(thermalManager.thermalStateDescription)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(stateColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(stateColor.opacity(0.12)))

                // Refresh Button
                Button {
                    thermalManager.isRefreshing = true
                    thermalManager.refreshMetrics()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        thermalManager.isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(thermalManager.isRefreshing ? 360 : 0))
                        .animation(thermalManager.isRefreshing ? .linear(duration: 0.4) : .default, value: thermalManager.isRefreshing)
                        .padding(5)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("Làm mới cảm biến nhiệt ngay lập tức")
            }
        }
        .macMateCard(padding: 12)
    }

    // MARK: - 2. Menu Bar Monitor (temperature only)

    private var menuBarMonitorRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "menubar.dock.rectangle")
                .font(.system(size: 9))
                .foregroundStyle(Color.accentColor)

            Text("Hiện nhiệt độ trên Menu Bar")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            Spacer()

            if thermalManager.showMenuBarMetrics {
                Text(thermalManager.cpuAvgTemp > 0 ? "\(Int(thermalManager.cpuAvgTemp))°C" : "—")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.cyan)
            }

            Toggle("", isOn: Binding<Bool>(
                get: { thermalManager.showMenuBarMetrics },
                set: { thermalManager.showMenuBarMetrics = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .macMateCard(padding: 10)
    }

    // MARK: - 3. Thermal Matrix (6 Metrics)
    private var thermalMatrixGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(thermalManager.isIntelMac ? "Bản đồ nhiệt Intel (SMC)" : "Bản đồ nhiệt Apple Silicon (HID PMU)", systemImage: "cpu")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("Thời gian thực: 2.5s")
                    .font(.system(size: 7.5))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                sensorTile(
                    title: "CPU Trung bình",
                    temp: thermalManager.cpuAvgTemp,
                    icon: "cpu",
                    sub: "Tất cả các nhân"
                )
                sensorTile(
                    title: "CPU Nóng nhất",
                    temp: thermalManager.cpuPeakTemp,
                    icon: "flame.fill",
                    sub: "Core Peak Hotspot"
                )
                sensorTile(
                    title: "GPU Đồ họa",
                    temp: thermalManager.gpuAvgTemp,
                    icon: "gamecontroller.fill",
                    sub: "Cụm nhân GPU"
                )
                sensorTile(
                    title: "Pin Cell",
                    temp: thermalManager.batteryTemp,
                    icon: "battery.100.bolt",
                    sub: "Gas Gauge Pack"
                )
                sensorTile(
                    title: "Ổ cứng SSD",
                    temp: thermalManager.ssdTemp,
                    icon: "internaldrive.fill",
                    sub: "NAND Flash Storage"
                )
                sensorTile(
                    title: "Hotspot Bo mạch",
                    temp: thermalManager.hotspotTemp,
                    icon: "thermometer.sun.fill",
                    sub: "PMU Calibration"
                )
            }
        }
        .macMateCard(padding: 12)
    }

    private func sensorTile(title: String, temp: Double, icon: String, sub: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tempColor(temp))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(temp > 0 ? String(format: "%.1f°C", temp) : "—")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(tempColor(temp))

                Text(sub)
                    .font(.system(size: 6.8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4.5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }

    // MARK: - 4. Detailed Sensor Breakdown Accordion
    private var detailedSensorsAccordion: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    thermalManager.isDetailExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.accentColor)

                    Text("Chi tiết \(thermalManager.detailedSensors.count) cảm biến \(thermalManager.isIntelMac ? "SMC" : "PMU")")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: thermalManager.isDetailExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)

            if thermalManager.isDetailExpanded {
                VStack(spacing: 3) {
                    ForEach(thermalManager.detailedSensors) { s in
                        HStack {
                            Text(s.displayName)
                                .font(.system(size: 7.5, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("(\(s.name))")
                                .font(.system(size: 6.8))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(String(format: "%.1f°C", s.temp))
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(tempColor(s.temp))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.02)))
            }
        }
    }

    private func tempColor(_ temp: Double) -> Color {
        guard temp > 0 else { return .secondary }
        if temp < 55.0 {
            return .green
        } else if temp < 75.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var stateColor: Color {
        if thermalManager.isThrottling {
            return .red
        }
        let peak = thermalManager.cpuPeakTemp
        if peak < 60.0 {
            return .green
        } else if peak < 80.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var headerIconColor: Color {
        Color.cyan
    }

    private var headerIconBackground: Color {
        Color.cyan.opacity(0.12)
    }
}
