import SwiftUI

// swiftui-navigation: NavigationStack + sheet；swiftui-layout-components: Form + Section + LabeledContent
struct PermissionCheckView: View {
    var shortcutManager: ShortcutManager?
    var isLaunchGate: Bool = false
    var onGranted: (() -> Void)?
    var onDismiss: (() -> Void)?

    @State private var isGranted = AccessibilityPermissionManager.shared.checkAccessibilityPermission()

    private let permissionManager = AccessibilityPermissionManager.shared

    private var isGlobalMonitorActive: Bool {
        shortcutManager?.isGlobalMonitorActive ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                detailsSection
                stepsSection
            }
            .formStyle(.grouped)
            .navigationTitle("permission.check.title".localized)
            .toolbar {
                if !isLaunchGate {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("button.cancel".localized) {
                            onDismiss?()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("permission.check.recheck".localized) {
                        refreshStatus()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
        }
        .frame(minWidth: 520, minHeight: 460)
        .onAppear {
            refreshStatus()
            permissionManager.startMonitoringPermission { granted in
                if granted {
                    shortcutManager?.restartGlobalMonitorIfNeeded()
                    refreshStatus()
                    onGranted?()
                }
            }
        }
        .onDisappear {
            permissionManager.stopMonitoringPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
            shortcutManager?.restartGlobalMonitorIfNeeded()
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(isGranted ? .green : .orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isGranted ? "permission.check.granted".localized : "permission.check.missing".localized)
                        .font(.headline)
                    Text(isGranted ? "permission.check.granted.detail".localized : "permission.check.missing.detail".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var detailsSection: some View {
        Section("permission.check.details".localized) {
            LabeledContent("permission.check.app_path".localized) {
                Text(permissionManager.runningAppPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("permission.check.global_shortcuts".localized) {
                Label(
                    isGlobalMonitorActive ? "permission.check.active".localized : "permission.check.inactive".localized,
                    systemImage: isGlobalMonitorActive ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(isGlobalMonitorActive ? .green : .secondary)
                .font(.caption)
            }
        }
    }

    private var stepsSection: some View {
        Section("permission.check.steps".localized) {
            permissionStepRow(number: 1, text: "permission.check.step.open_settings".localized)
            permissionStepRow(number: 2, text: "permission.check.step.enable_app".localized)
            permissionStepRow(number: 3, text: "permission.check.step.return".localized)

            Text("permission.check.path_note".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        HStack {
            if isLaunchGate && !isGranted {
                Button("permission.check.later".localized) {
                    onDismiss?()
                }
                .buttonStyle(.glass)
            }

            Spacer()

            if isGranted {
                Button("button.done".localized) {
                    onGranted?()
                    onDismiss?()
                }
                .buttonStyle(.glassProminent)
            } else {
                Button {
                    permissionManager.openAccessibilitySettings()
                } label: {
                    Label("permission.open_settings".localized, systemImage: "gearshape")
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private func permissionStepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    private func refreshStatus() {
        isGranted = permissionManager.checkAccessibilityPermission()
        if isGranted {
            shortcutManager?.restartGlobalMonitorIfNeeded()
        }
    }
}
