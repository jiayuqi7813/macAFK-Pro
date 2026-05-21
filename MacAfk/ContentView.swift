import SwiftUI

struct ContentView: View {
    @ObservedObject var appModel: AppModel

    @State private var showingShortcutEditor = false
    @AccessibilityFocusState private var shortcutEditorTriggerFocused: Bool

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 22) {
                VStack(alignment: .leading, spacing: 22) {
                    StatusHeroCard(
                        isJiggling: appModel.isJiggling,
                        title: statusTitle
                    )

                    MainSettingsCard(appModel: appModel)

                    AgentActivityCard(appModel: appModel)

                    ShortcutSummaryCard(
                        shortcutManager: appModel.shortcutManager,
                        customizeAction: { showingShortcutEditor = true },
                        customizeFocused: $shortcutEditorTriggerFocused
                    )

                    PermissionHintFooter()
                }
            }
            .frame(maxWidth: 520, alignment: .top)
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .frame(width: 480)
        .frame(minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .showPreferencesRequested, object: nil)
                } label: {
                    Label("menu.preferences".localized, systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("menu.preferences".localized)
                .accessibilityLabel("menu.preferences".localized)
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .sheet(isPresented: $showingShortcutEditor) {
            ShortcutEditorView(shortcutManager: appModel.shortcutManager)
                .presentationSizing(.form)
                .onDisappear {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        shortcutEditorTriggerFocused = true
                    }
                }
        }
    }

    private var statusTitle: String {
        appModel.isJiggling
            ? "status.preventing_sleep".localized
            : "status.system_sleep_allowed".localized
    }
}

private struct StatusHeroCard: View {
    let isJiggling: Bool
    let title: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    var body: some View {
        VStack(spacing: 12) {
            statusIcon

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.86)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .padding(.horizontal, 24)
        .nativeGlassPanel(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: some View {
        Group {
            if reduceMotion {
                Image(systemName: iconName)
                    .font(.system(size: iconSize))
                    .foregroundStyle(iconColor)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: iconSize))
                    .foregroundStyle(iconColor)
                    .symbolEffect(.bounce, value: isJiggling)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .accessibilityLabel(title)
    }

    private var iconName: String {
        isJiggling ? "sleep.circle.fill" : "sleep"
    }

    private var iconColor: Color {
        isJiggling ? .green : .secondary
    }
}

private struct MainSettingsCard: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.macafk_settings".localized)
                .font(.headline)

            VStack(spacing: 0) {
                Button(action: { appModel.toggleJiggle() }) {
                    Text(
                        appModel.isJiggling
                            ? "button.stop_jiggling".localized
                            : "button.start_jiggling".localized
                    )
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.glassProminent)
                .tint(appModel.isJiggling ? .red : .green)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 14)

                Divider()

                IntervalRow(jiggler: appModel.jiggler)
                    .padding(.vertical, 12)

                Divider()

                LowBrightnessRow(appModel: appModel)
                    .padding(.vertical, 12)

                Divider()

                AutoLockTimerRow(appModel: appModel)
                    .padding(.vertical, 12)

                Divider()

                AgentAutoLockRow(appModel: appModel)
                    .padding(.vertical, 12)

                Divider()

                LaunchAtLoginRow(appModel: appModel)
                    .padding(.top, 12)
            }
            .padding(14)
            .nativeGlassPanel(cornerRadius: 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("settings.launch_at_login.error.title".localized, isPresented: Binding(
            get: { appModel.launchAtLoginError != nil },
            set: { if !$0 { appModel.launchAtLoginError = nil } }
        )) {
            Button("button.done".localized) {
                appModel.launchAtLoginError = nil
            }
        } message: {
            if let error = appModel.launchAtLoginError {
                Text(error)
            }
        }
    }
}

private struct IntervalRow: View {
    @ObservedObject var jiggler: Jiggler

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("jiggle.interval".localized)
                .font(.body.weight(.semibold))

            Spacer(minLength: 16)

            Text(jiggler.getIntervalDisplay())
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .frame(width: 72, alignment: .trailing)
                .contentTransition(.numericText())
                .accessibilityValue(jiggler.getIntervalDisplay())

            Button(action: { jiggler.decreaseInterval() }) {
                Image(systemName: "minus.circle")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("jiggle.interval.decrease".localized)
            .accessibilityLabel("jiggle.interval.decrease".localized)

            Button(action: { jiggler.increaseInterval() }) {
                Image(systemName: "plus.circle")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("jiggle.interval.increase".localized)
            .accessibilityLabel("jiggle.interval.increase".localized)
        }
    }
}

private struct LowBrightnessRow: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("settings.low_brightness_mode".localized, isOn: $appModel.isLowBrightness)
                    .toggleStyle(.checkbox)
                    .font(.body.weight(.semibold))
                    .help("settings.low_brightness_mode.help".localized)

                Spacer(minLength: 0)
            }

            Text("settings.low_brightness_mode.description".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(appModel.brightnessControl.issues) { issue in
                Label(issue.localizedMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AutoLockTimerRow: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                Toggle("timer.auto_lock.enabled".localized, isOn: $appModel.autoLockTimerEnabled)
                    .toggleStyle(.checkbox)
                    .font(.body.weight(.semibold))
                    .help("timer.auto_lock.help".localized)

                Spacer(minLength: 16)

                Text(appModel.getAutoLockDurationDisplay())
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .frame(width: 96, alignment: .trailing)
                    .contentTransition(.numericText())

                Button(action: { appModel.decreaseAutoLockDuration() }) {
                    Image(systemName: "minus.circle")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("timer.auto_lock.decrease".localized)
                .accessibilityLabel("timer.auto_lock.decrease".localized)

                Button(action: { appModel.increaseAutoLockDuration() }) {
                    Image(systemName: "plus.circle")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("timer.auto_lock.increase".localized)
                .accessibilityLabel("timer.auto_lock.increase".localized)
            }

            Text("timer.auto_lock.description".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if appModel.autoLockEndDate != nil {
                Label(
                    String(format: "timer.auto_lock.remaining".localized, appModel.getAutoLockRemainingDisplay()),
                    systemImage: "timer"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LaunchAtLoginRow: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        HStack {
            Toggle("settings.launch_at_login".localized, isOn: $appModel.launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.body.weight(.semibold))
                .help("settings.launch_at_login.help".localized)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentAutoLockRow: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("agent.auto_lock.enabled".localized, isOn: $appModel.agentAutoLockEnabled)
                    .toggleStyle(.checkbox)
                    .font(.body.weight(.semibold))
                    .help("agent.auto_lock.help".localized)

                Spacer(minLength: 0)
            }

            Text("agent.auto_lock.description".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if appModel.activeAgentSessionCount > 0 {
                Label(
                    String(format: "agent.auto_lock.active_count".localized, appModel.activeAgentSessionCount),
                    systemImage: "bolt.horizontal.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            } else if appModel.agentAutoLockEndDate != nil {
                Label(
                    String(format: "agent.auto_lock.remaining".localized, appModel.getAgentAutoLockRemainingDisplay()),
                    systemImage: "timer"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentActivityCard: View {
    @ObservedObject var appModel: AppModel

    @State private var isExpanded = false

    private let collapsedRowLimit = 2

    var body: some View {
        let agents = appModel.activeAgentSessionsList
        let visibleAgents = isExpanded ? agents : Array(agents.prefix(collapsedRowLimit))

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("agent.activity.title".localized, systemImage: "bolt.horizontal.circle.fill")
                    .font(.headline)

                Spacer(minLength: 12)

                if appModel.activeAgentSessionCount > 0 {
                    Text(String(format: "agent.activity.count".localized, appModel.activeAgentSessionCount))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }

            VStack(spacing: 0) {
                if agents.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("agent.activity.empty".localized, systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(appModel.agentHookStatusMessage.isEmpty ? "agent.activity.hook_hint".localized : appModel.agentHookStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else {
                    ForEach(visibleAgents.indices, id: \.self) { index in
                        let event = visibleAgents[index]

                        if index > 0 {
                            Divider()
                        }

                        AgentActivityRow(event: event)
                            .padding(.vertical, 10)
                    }

                    if agents.count > collapsedRowLimit {
                        Divider()

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .frame(width: 16)

                                Text(expandButtonTitle(totalCount: agents.count))
                                    .lineLimit(1)

                                Spacer(minLength: 0)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(expandButtonTitle(totalCount: agents.count))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .nativeGlassPanel(cornerRadius: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expandButtonTitle(totalCount: Int) -> String {
        if isExpanded {
            return "agent.activity.collapse".localized
        }

        return String(
            format: "agent.activity.expand".localized,
            max(totalCount - collapsedRowLimit, 0)
        )
    }
}

private struct AgentActivityRow: View {
    let event: AgentHookEvent

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(event.iconAssetName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.softwareDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(event.taskDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text("\(event.eventName) · \(String(format: "agent.activity.session".localized, event.shortSessionID))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            Text("agent.activity.running".localized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .help(event.cwd ?? event.id)
    }
}

private struct ShortcutSummaryCard: View {
    @ObservedObject var shortcutManager: ShortcutManager
    let customizeAction: () -> Void

    let customizeFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.title".localized)
                .font(.headline)

            VStack(spacing: 0) {
                ShortcutDisplayRow(
                    title: "shortcut.toggle_jiggle".localized,
                    icon: "power",
                    color: .green,
                    shortcut: shortcutManager.getShortcutDisplay(for: .toggleJiggle)
                )

                Divider()

                ShortcutDisplayRow(
                    title: "shortcut.toggle_brightness".localized,
                    icon: "sun.max",
                    color: .orange,
                    shortcut: shortcutManager.getShortcutDisplay(for: .toggleBrightness)
                )

                Divider()

                HStack {
                    Button(action: customizeAction) {
                        Label("button.customize_all_shortcuts".localized, systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.glass)
                    .accessibilityFocused(customizeFocused)

                    Spacer()
                }
                .padding(.top, 12)
            }
            .padding(14)
            .nativeGlassPanel(cornerRadius: 16)
        }
    }
}

private struct ShortcutDisplayRow: View {
    let title: String
    let icon: String
    let color: Color
    let shortcut: String

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: icon)
                .foregroundStyle(color)
                .font(.body.weight(.semibold))

            Spacer(minLength: 12)

            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionHintFooter: View {
    var body: some View {
        Text("footer.permission_hint".localized)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .nativeGlassPanel(cornerRadius: 16)
    }
}

private struct NativeGlassPanel: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

private extension View {
    func nativeGlassPanel(cornerRadius: CGFloat) -> some View {
        modifier(NativeGlassPanel(cornerRadius: cornerRadius))
    }
}
