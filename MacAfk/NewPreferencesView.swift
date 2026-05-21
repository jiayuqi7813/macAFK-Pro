import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case displays
    case general
    case language
    case update

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .displays: return "display.2"
        case .general: return "gearshape.fill"
        case .language: return "globe"
        case .update: return "arrow.down.circle"
        }
    }

    var localizedKey: String {
        switch self {
        case .displays: return "settings.displays"
        case .general: return "settings.general"
        case .language: return "menu.language"
        case .update: return "update.check_for_updates"
        }
    }
}

// swiftui-navigation: NavigationSplitView 设置风格；swiftui-patterns: platform-and-sharing macOS Settings
struct NewPreferencesView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var appModel: AppModel

    @StateObject private var updateManager = UpdateManager.shared
    @StateObject private var betterDisplayManager = BetterDisplayManager.shared

    @State private var selectedDisplayID: String?
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    @State private var showRestartAlert = false
    @State private var previewBrightness: Float = 0.0
    @State private var isPreviewing = false
    @State private var updateRelease: GitHubRelease?

    @State private var testBrightness: Float = 0.5
    @State private var currentBrightness: Float?
    @State private var testMessage: String = ""
    @State private var isTestingBrightness = false

    @State private var showEnvironmentCheck = false
    @State private var showPermissionCheck = false
    @State private var isCheckingEnvironment = false
    @State private var checkResults: (installed: Bool, running: Bool, connected: Bool) = (false, false, false)

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            List {
                Section {
                    ForEach(SettingsTab.allCases) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.localizedKey.localized, systemImage: tab.icon)
                                .font(.title3.weight(.medium))
                                .padding(.vertical, 5)
                        }
                    }
                }
            }
            .navigationDestination(for: SettingsTab.self) { tab in
                NavigationStack {
                    detailContent(for: tab)
                }
            }
            .listStyle(.sidebar)
            .contentMargins(.top, 74, for: .scrollContent)
            .frame(minWidth: 280)
            .navigationSplitViewColumnWidth(min: 300, ideal: 315, max: 340)
        } detail: {
            NavigationStack {
                detailContent(for: .displays)
            }
        }
        .frame(
            minWidth: 900,
            idealWidth: 1_180,
            maxWidth: 1_520,
            minHeight: 560,
            idealHeight: 720,
            maxHeight: 980
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                } label: {
                    Label("sidebar.toggle".localized, systemImage: "sidebar.left")
                }
                .labelStyle(.iconOnly)
                .help("sidebar.toggle".localized)
                .accessibilityLabel("sidebar.toggle".localized)
            }
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            previewBrightness = appModel.lowBrightnessLevel
            appModel.refreshAgentHookStatus()
            betterDisplayManager.checkInstallation()
            if betterDisplayManager.isInstalled && betterDisplayManager.isEnabled {
                betterDisplayManager.refreshDisplays()
            }
        }
        .onDisappear {
            if isPreviewing {
                appModel.brightnessControl.restoreBrightness()
                isPreviewing = false
            }
        }
        .alert("menu.language.restart_required".localized, isPresented: $showRestartAlert) {
            Button("button.done".localized) {
                showRestartAlert = false
            }
        }
        .alert("agent.hooks.error.title".localized, isPresented: Binding(
            get: { appModel.agentHookSetupError != nil },
            set: { if !$0 { appModel.agentHookSetupError = nil } }
        )) {
            Button("button.done".localized) {
                appModel.agentHookSetupError = nil
            }
        } message: {
            if let error = appModel.agentHookSetupError {
                Text(error)
            }
        }
        .sheet(item: $updateRelease) { release in
            UpdateAlertView(updateManager: updateManager, release: release)
                .presentationSizing(.form)
        }
        .sheet(isPresented: $showEnvironmentCheck) {
            environmentCheckDialog
        }
        .sheet(isPresented: $showPermissionCheck) {
            PermissionCheckView(
                shortcutManager: appModel.shortcutManager,
                onGranted: {
                    showPermissionCheck = false
                },
                onDismiss: {
                    showPermissionCheck = false
                }
            )
            .presentationSizing(.form)
        }
        .onChange(of: updateManager.updateStatus) { _, newStatus in
            if case .available(let release) = newStatus {
                updateRelease = release
            }
        }
    }

    @ViewBuilder
    private func detailContent(for tab: SettingsTab) -> some View {
        Group {
            switch tab {
            case .displays:
                displaysContent
            case .general:
                generalContent
            case .language:
                languageContent
            case .update:
                updateContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Displays

    private var displaysContent: some View {
        Form {
            betterDisplaySection

            if betterDisplayManager.isEnabled {
                displaySelectionSection
            }

            if let display = selectedDisplay {
                displayInfoSections(for: display)
                displayBrightnessTestSection(for: display)
            } else {
                globalBrightnessSections
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: selectedDisplayID) { _, _ in
            currentBrightness = nil
            testMessage = ""
        }
    }

    private var selectedDisplay: BetterDisplayInfo? {
        guard let selectedDisplayID else { return nil }
        return betterDisplayManager.displays.first { $0.id == selectedDisplayID }
    }

    @ViewBuilder
    private var betterDisplaySection: some View {
        Section("betterdisplay.title".localized) {
            if betterDisplayManager.isInstalled {
                Label(
                    betterDisplayManager.isRunning
                        ? "betterdisplay.running".localized
                        : "betterdisplay.not_running".localized,
                    systemImage: betterDisplayManager.isRunning ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(betterDisplayManager.isRunning ? .green : .secondary)
                .font(.caption)

                Toggle("betterdisplay.enable_integration".localized, isOn: Binding(
                    get: { betterDisplayManager.isEnabled },
                    set: { newValue in
                        betterDisplayManager.setEnabled(newValue)
                        appModel.brightnessControl.updateDisplayMapping()
                        if newValue {
                            betterDisplayManager.testConnection { success in
                                if success {
                                    betterDisplayManager.refreshDisplays()
                                }
                            }
                        }
                    }
                ))
                .disabled(!betterDisplayManager.isRunning)

                HStack {
                    if betterDisplayManager.isEnabled {
                        Button("betterdisplay.refresh_displays".localized) {
                            betterDisplayManager.refreshDisplays()
                            appModel.brightnessControl.updateDisplayMapping()
                        }
                        .buttonStyle(.glass)
                    }

                    Button("betterdisplay.test_connection".localized) {
                        betterDisplayManager.testConnection { success in
                            if success {
                                betterDisplayManager.refreshDisplays()
                            }
                        }
                    }
                    .buttonStyle(.glass)

                    Button("betterdisplay.environment_check".localized) {
                        performEnvironmentCheck()
                    }
                    .buttonStyle(.glass)

                    Spacer()
                }
            } else {
                Label("betterdisplay.not_installed".localized, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)

                Button("betterdisplay.open_app".localized) {
                    if let url = URL(string: "https://github.com/waydabber/BetterDisplay") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }

    @ViewBuilder
    private var displaySelectionSection: some View {
        Section("betterdisplay.display_list".localized) {
            if betterDisplayManager.displays.isEmpty {
                Label(
                    "betterdisplay.no_displays".localized,
                    systemImage: "display.trianglebadge.exclamationmark"
                )
                .foregroundStyle(.secondary)
            } else {
                displaySelectionButton(
                    title: "settings.low_brightness".localized,
                    detail: nil,
                    id: nil
                )

                ForEach(betterDisplayManager.displays) { display in
                    displaySelectionButton(
                        title: display.name,
                        detail: display.displayID.map { "ID: \($0)" },
                        id: display.id
                    )
                }
            }
        }
    }

    private func displaySelectionButton(title: String, detail: String?, id: String?) -> some View {
        Button {
            selectedDisplayID = id
        } label: {
            DisplaySelectionRow(
                title: title,
                detail: detail,
                isSelected: selectedDisplayID == id
            )
        }
        .buttonStyle(.plain)
    }

    private struct DisplaySelectionRow: View {
        let title: String
        let detail: String?
        let isSelected: Bool

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .lineLimit(1)

                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .clear)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var globalBrightnessSections: some View {
        Section("settings.low_brightness".localized) {
            Text("settings.brightness_preview_hint".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("settings.brightness_level".localized) {
                Text("\(Int(appModel.lowBrightnessLevel * 100))%")
                    .monospacedDigit()
            }

            Slider(value: Binding(
                get: { appModel.lowBrightnessLevel },
                set: { newValue in
                    appModel.lowBrightnessLevel = newValue
                    if isPreviewing {
                        previewBrightness = newValue
                        appModel.brightnessControl.setCustomBrightness(level: newValue)
                    }
                }
            ), in: 0...1)

            HStack {
                Button {
                    if isPreviewing {
                        appModel.brightnessControl.restoreBrightness()
                        isPreviewing = false
                    } else {
                        previewBrightness = appModel.lowBrightnessLevel
                        appModel.brightnessControl.setLowestBrightness(level: appModel.lowBrightnessLevel)
                        isPreviewing = true
                    }
                } label: {
                    Label(
                        isPreviewing ? "settings.stop_preview".localized : "settings.preview_brightness".localized,
                        systemImage: isPreviewing ? "eye.slash.fill" : "eye.fill"
                    )
                }
                .buttonStyle(.glass)

                if isPreviewing {
                    Button("settings.restore_brightness".localized) {
                        appModel.brightnessControl.restoreBrightness()
                        isPreviewing = false
                    }
                    .buttonStyle(.glass)
                }
            }
        }

        if !appModel.brightnessControl.issues.isEmpty {
            Section {
                ForEach(appModel.brightnessControl.issues) { issue in
                    Label(issue.localizedMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }

        Section {
            if !betterDisplayManager.isEnabled {
                Label("betterdisplay.disabled_warning".localized, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                Label("betterdisplay.integration_hint".localized, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }

        if betterDisplayManager.isEnabled && betterDisplayManager.displays.isEmpty {
            Section {
                Button("betterdisplay.refresh_displays".localized) {
                    betterDisplayManager.refreshDisplays()
                    appModel.brightnessControl.updateDisplayMapping()
                }
                .buttonStyle(.glass)
            }
        }

        if !betterDisplayManager.isEnabled {
            Section {
                Text("betterdisplay.enable_hint".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func displayInfoSections(for display: BetterDisplayInfo) -> some View {
        Section(display.name) {
            if let productName = display.productName {
                LabeledContent("display.info.model".localized, value: productName)
            }
        }

        Section("display.info".localized) {
            if let displayID = display.displayID {
                LabeledContent("display.info.display_id".localized, value: displayID)
            }
            if let uuid = display.UUID {
                LabeledContent("display.info.uuid".localized, value: uuid)
            }
            if let serial = display.serial {
                LabeledContent("display.info.serial".localized, value: serial)
            }
            if let model = display.model {
                LabeledContent("display.info.model".localized, value: model)
            }
            if let vendor = display.vendor {
                LabeledContent("display.info.vendor".localized, value: vendor)
            }
            if let alphanumericSerial = display.alphanumericSerial, !alphanumericSerial.isEmpty {
                LabeledContent("display.info.alphanumeric_serial".localized, value: alphanumericSerial)
            }
            if let year = display.yearOfManufacture, let week = display.weekOfManufacture {
                LabeledContent("display.info.manufacture_date".localized, value: "\(year) / \(week)")
            }
        }
    }

    @ViewBuilder
    private func displayBrightnessTestSection(for display: BetterDisplayInfo) -> some View {
        Section("display.brightness_test".localized) {
            LabeledContent("display.brightness_test.get_current".localized) {
                HStack {
                    Button("display.brightness_test.get_button".localized) {
                        fetchCurrentBrightness(for: display)
                    }
                    .buttonStyle(.glass)
                    .disabled(isTestingBrightness || display.UUID == nil)

                    if isTestingBrightness {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let brightness = currentBrightness {
                        Text("\(Int(brightness * 100))%")
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                }
            }

            LabeledContent("display.brightness_test.set_target".localized) {
                Text("\(Int(testBrightness * 100))%")
                    .monospacedDigit()
            }

            Slider(value: $testBrightness, in: 0...1)

            Button("display.brightness_test.set_button".localized) {
                setTestBrightness(for: display)
            }
            .buttonStyle(.glassProminent)
            .disabled(isTestingBrightness || display.UUID == nil)

            if !testMessage.isEmpty {
                Text(testMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("display.brightness_test.hint".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - General

    private var generalContent: some View {
        Form {
            Section("settings.macafk_settings".localized) {
                Toggle("settings.launch_at_login".localized, isOn: $appModel.launchAtLogin)
                    .help("settings.launch_at_login.help".localized)
            }

            Section("agent.auto_lock.title".localized) {
                Toggle("agent.auto_lock.enabled".localized, isOn: $appModel.agentAutoLockEnabled)
                    .help("agent.auto_lock.help".localized)

                LabeledContent("agent.hooks.status".localized) {
                    Text(appModel.agentHookStatusMessage)
                        .foregroundStyle(appModel.agentHookInstallSummary.hasAnyInstalled ? .green : .secondary)
                }

                if appModel.activeAgentSessionCount > 0 {
                    LabeledContent("agent.auto_lock.active_agents".localized) {
                        Text("\(appModel.activeAgentSessionCount)")
                            .monospacedDigit()
                    }
                }

                if appModel.agentAutoLockEndDate != nil {
                    LabeledContent("agent.auto_lock.countdown".localized) {
                        Text(appModel.getAgentAutoLockRemainingDisplay())
                            .monospacedDigit()
                    }
                }

                HStack {
                    Button("agent.hooks.install".localized) {
                        appModel.installAgentHooks()
                    }
                    .buttonStyle(.glassProminent)

                    Button("agent.hooks.uninstall".localized) {
                        appModel.uninstallAgentHooks()
                    }
                    .buttonStyle(.glass)

                    Button("agent.hooks.refresh".localized) {
                        appModel.refreshAgentHookStatus()
                    }
                    .buttonStyle(.glass)
                }

                Text("agent.auto_lock.setup_note".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("permission.check.title".localized) {
                LabeledContent("permission.check.status".localized) {
                    Label(
                        permissionStatusText,
                        systemImage: permissionStatusIcon
                    )
                    .foregroundStyle(permissionStatusColor)
                    .font(.subheadline)
                }

                LabeledContent("permission.check.install_location".localized) {
                    Text(AppUpdateInstaller.preferredInstallURL().path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }

                Button("permission.check.button".localized) {
                    showPermissionCheck = true
                }
                .buttonStyle(.glassProminent)

                Text("permission.check.settings_note".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("settings.debug".localized) {
                Toggle("debug.skip_permission_prompts".localized, isOn: $appModel.skipPermissionPrompts)
                    .help("debug.skip_permission_prompts.help".localized)

                Text("debug.skip_permission_prompts.note".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Language

    private var languageContent: some View {
        Form {
            Section {
                Text("menu.language.restart_required".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("menu.language".localized) {
                Picker("menu.language".localized, selection: Binding(
                    get: { languageManager.currentLanguage },
                    set: { language in
                        if languageManager.currentLanguage != language {
                            languageManager.setLanguage(language)
                            showRestartAlert = true
                        }
                    }
                )) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.localizedDisplayName).tag(language)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Update

    private var updateContent: some View {
        Form {
            Section {
                LabeledContent("update.current_version".localized) {
                    Text(getCurrentVersion())
                        .font(.system(.body, design: .monospaced))
                }
                updateStatusView
            }

            Section {
                Button("update.check_now".localized) {
                    updateManager.checkForUpdates(silent: false)
                }
                .buttonStyle(.glass)
                .disabled(isCheckingUpdate)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateManager.updateStatus {
        case .checking:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("update.checking".localized)
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("update.up_to_date".localized, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available(let release):
            Label(
                "update.new_version_available".localized + ": \(release.tagName)",
                systemImage: "arrow.down.circle.fill"
            )
            .foregroundStyle(.blue)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .installing:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("update.installing.in_place".localized)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Environment Check

    private var environmentCheckDialog: some View {
        NavigationStack {
            Group {
                if isCheckingEnvironment {
                    ProgressView("betterdisplay.environment_check.checking".localized)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        checkResultRow(
                            icon: checkResults.installed ? "checkmark.circle.fill" : "xmark.circle.fill",
                            color: checkResults.installed ? .green : .red,
                            title: "betterdisplay.environment_check.install".localized,
                            status: checkResults.installed
                                ? "betterdisplay.environment_check.installed".localized
                                : "betterdisplay.environment_check.not_installed_status".localized,
                            action: checkResults.installed ? nil : {
                                if let url = URL(string: "https://github.com/waydabber/BetterDisplay") {
                                    NSWorkspace.shared.open(url)
                                }
                            },
                            actionTitle: "betterdisplay.environment_check.download".localized
                        )

                        checkResultRow(
                            icon: checkResults.running ? "checkmark.circle.fill" : "xmark.circle.fill",
                            color: checkResults.running ? .green : .red,
                            title: "betterdisplay.environment_check.running".localized,
                            status: checkResults.running
                                ? "betterdisplay.running".localized
                                : "betterdisplay.not_running".localized,
                            action: !checkResults.running && checkResults.installed ? {
                                if let url = URL(string: "file:///Applications/BetterDisplay.app") {
                                    NSWorkspace.shared.open(url)
                                }
                            } : nil,
                            actionTitle: "betterdisplay.environment_check.launch".localized
                        )

                        checkResultRow(
                            icon: checkResults.connected ? "checkmark.circle.fill" : "xmark.circle.fill",
                            color: checkResults.connected ? .green : .red,
                            title: "betterdisplay.environment_check.connection".localized,
                            status: checkResults.connected
                                ? "betterdisplay.connection_success".localized
                                : "betterdisplay.connection_failed".localized,
                            action: !checkResults.connected && checkResults.running ? {
                                if let url = URL(string: "https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI") {
                                    NSWorkspace.shared.open(url)
                                }
                            } : nil,
                            actionTitle: "betterdisplay.environment_check.guide".localized
                        )

                        if !checkResults.connected && checkResults.running {
                            Section {
                                VStack(alignment: .leading) {
                                    Text("betterdisplay.environment_check.failure_title".localized)
                                        .font(.subheadline.weight(.semibold))
                                    Text("betterdisplay.environment_check.failure_reason_1".localized)
                                        .font(.caption)
                                    Text("betterdisplay.environment_check.failure_reason_2".localized)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .navigationTitle("betterdisplay.environment_check.title".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("betterdisplay.environment_check.recheck".localized) {
                        performEnvironmentCheck()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("button.done".localized) {
                        showEnvironmentCheck = false
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .presentationSizing(.form)
    }

    private func checkResultRow(
        icon: String,
        color: Color,
        title: String,
        status: String,
        action: (() -> Void)?,
        actionTitle: String
    ) -> some View {
        Section {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                if let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Helpers

    private func closePreferencesWindow() {
        NSApp.keyWindow?.close()
    }

    private func configurePreferencesWindowChrome() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.canBecomeKey }) else { return }

            let minimumSize = NSSize(width: 760, height: 540)
            let idealSize = NSSize(width: 860, height: 620)
            let maximumSize = NSSize(width: 980, height: 720)
            let currentSize = window.contentLayoutRect.size

            window.title = "settings.window_title".localized
            window.titlebarSeparatorStyle = .none
            window.contentMinSize = minimumSize
            window.contentMaxSize = maximumSize

            if currentSize.width < minimumSize.width
                || currentSize.height < minimumSize.height
                || currentSize.width > maximumSize.width
                || currentSize.height > maximumSize.height {
                window.setContentSize(idealSize)
                window.center()
            }
        }
    }

    private func getCurrentVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return "v\(version)"
        }
        return "v1.0.0"
    }

    private var isCheckingUpdate: Bool {
        if case .checking = updateManager.updateStatus {
            return true
        }
        return false
    }

    private var permissionStatusText: String {
        AccessibilityPermissionManager.shared.checkAccessibilityPermission()
            ? "permission.check.granted".localized
            : "permission.check.missing".localized
    }

    private var permissionStatusIcon: String {
        AccessibilityPermissionManager.shared.checkAccessibilityPermission()
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    private var permissionStatusColor: Color {
        AccessibilityPermissionManager.shared.checkAccessibilityPermission()
            ? .green
            : .orange
    }

    private func performEnvironmentCheck() {
        isCheckingEnvironment = true
        showEnvironmentCheck = true

        betterDisplayManager.checkInstallation()
        checkResults.installed = betterDisplayManager.isInstalled

        betterDisplayManager.checkIfRunning()
        checkResults.running = betterDisplayManager.isRunning

        if checkResults.installed && checkResults.running {
            betterDisplayManager.testConnection { success in
                DispatchQueue.main.async {
                    checkResults.connected = success
                    isCheckingEnvironment = false
                }
            }
        } else {
            checkResults.connected = false
            isCheckingEnvironment = false
        }
    }

    private func fetchCurrentBrightness(for display: BetterDisplayInfo) {
        guard let uuid = display.UUID else {
            testMessage = "display.brightness_test.no_uuid".localized
            return
        }

        isTestingBrightness = true
        testMessage = "display.brightness_test.fetching".localized

        betterDisplayManager.cacheBrightnessByUUID(uuid: uuid) { brightness in
            DispatchQueue.main.async {
                isTestingBrightness = false
                if let brightness {
                    currentBrightness = brightness
                    testMessage = String(format: "display.brightness_test.current".localized, Int(brightness * 100))
                } else {
                    testMessage = "display.brightness_test.fetch_failed".localized
                }
            }
        }
    }

    private func setTestBrightness(for display: BetterDisplayInfo) {
        guard let uuid = display.UUID else {
            testMessage = "display.brightness_test.no_uuid".localized
            return
        }

        isTestingBrightness = true
        testMessage = "display.brightness_test.setting".localized

        betterDisplayManager.setBrightnessByUUID(uuid: uuid, brightness: testBrightness) { success in
            DispatchQueue.main.async {
                isTestingBrightness = false
                if success {
                    testMessage = String(format: "display.brightness_test.set_success".localized, Int(testBrightness * 100))
                } else {
                    testMessage = "display.brightness_test.set_failed".localized
                }
            }
        }
    }
}
