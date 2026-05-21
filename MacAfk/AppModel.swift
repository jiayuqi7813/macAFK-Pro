import Foundation
import SwiftUI
import Combine
import os

class AppModel: ObservableObject {
    @Published var isLowBrightness = false {
        didSet {
            if !isLoading {
                saveLowBrightnessMode()
            }
        }
    }
    @Published var lowBrightnessLevel: Float = 0.0 {
        didSet {
            if !isLoading {
                saveLowBrightnessLevel()
            }
        }
    }
    @Published var testBrightness: Float = 0.5
    @Published var launchAtLogin = false {
        didSet {
            guard !isLoading else { return }
            applyLaunchAtLoginChange()
        }
    }
    @Published var launchAtLoginError: String?
    @Published var skipPermissionPrompts = false {
        didSet {
            guard !isLoading else { return }
            saveSkipPermissionPrompts()
        }
    }
    @Published var autoLockTimerEnabled = false {
        didSet {
            guard !isLoading else { return }
            saveAutoLockTimerEnabled()
            if autoLockTimerEnabled {
                scheduleAutoLockTimerIfNeeded()
            } else {
                cancelAutoLockTimer()
            }
        }
    }
    @Published var autoLockDuration: TimeInterval = 30 * 60 {
        didSet {
            guard !isLoading else { return }
            saveAutoLockDuration()
            if autoLockTimerEnabled && jiggler.isRunning {
                scheduleAutoLockTimerIfNeeded()
            }
        }
    }
    @Published private(set) var autoLockEndDate: Date?
    @Published private(set) var autoLockRemaining: TimeInterval = 0
    @Published var agentAutoLockEnabled = false {
        didSet {
            guard !isLoading else { return }
            saveAgentAutoLockEnabled()
            if !agentAutoLockEnabled {
                cancelAgentAutoLockTimer()
            }
        }
    }
    @Published private(set) var activeAgentSessionCount = 0
    @Published private(set) var activeAgentSessionsList: [AgentHookEvent] = []
    @Published private(set) var agentAutoLockEndDate: Date?
    @Published private(set) var agentAutoLockRemaining: TimeInterval = 0
    @Published private(set) var agentHookInstallSummary = AgentHookInstallSummary()
    @Published private(set) var agentHookStatusMessage = ""
    @Published var agentHookSetupError: String?

    let jiggler = Jiggler()
    let brightnessControl = BrightnessControl()
    let shortcutManager = ShortcutManager()

    var isJiggling: Bool { jiggler.isRunning }

    private var cancellables = Set<AnyCancellable>()

    private let lowBrightnessKey = "app.lowBrightnessMode"
    private let lowBrightnessLevelKey = "app.lowBrightnessLevel"
    private let launchAtLoginKey = "app.launchAtLogin"
    private let autoLockTimerEnabledKey = "app.autoLockTimerEnabled"
    private let autoLockDurationKey = "app.autoLockDuration"
    private let agentAutoLockEnabledKey = "app.agentAutoLockEnabled"
    private let agentAutoLockDelay: TimeInterval = 5 * 60
    private let autoLockDurationPresets: [TimeInterval] = [5, 15, 30, 60, 120, 180].map { TimeInterval($0 * 60) }
    private var autoLockTimer: Timer?
    private var autoLockCountdownTimer: Timer?
    private var agentAutoLockTimer: Timer?
    private var agentAutoLockCountdownTimer: Timer?
    private var activeAgentSessions: [String: AgentHookEvent] = [:]
    private let agentHookMonitor = AgentHookMonitor()
    private var isLoading = false

    init() {
        loadLowBrightnessMode()
        loadLowBrightnessLevel()
        loadLaunchAtLogin()
        loadSkipPermissionPrompts()
        loadAutoLockTimerSettings()
        loadAgentAutoLockSettings()

        jiggler.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        shortcutManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        brightnessControl.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        shortcutManager.onAction = { [weak self] action in
            DispatchQueue.main.async {
                self?.handleShortcutAction(action)
            }
        }
        shortcutManager.startListening()
        startAgentHookMonitoring()
        refreshAgentHookStatus()
    }

    private func handleShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .toggleJiggle:
            toggleJiggle()
        case .toggleBrightness:
            toggleBrightnessMode()
        case .increaseJiggleInterval:
            jiggler.increaseInterval()
        case .decreaseJiggleInterval:
            jiggler.decreaseInterval()
        }
    }

    func toggleJiggle() {
        if !jiggler.isRunning && !AccessibilityPermissionManager.shared.checkAccessibilityPermission() {
            AccessibilityPermissionManager.shared.promptSystemAccessibilityPermission()
        }

        if jiggler.isRunning {
            stopJiggling(cancelTimer: true)
        } else {
            startJiggling()
        }

        NotificationCenter.default.post(name: .appModelStateChanged, object: nil)
    }

    func toggleBrightnessMode() {
        isLowBrightness.toggle()
        if jiggler.isRunning {
            if isLowBrightness {
                brightnessControl.setLowestBrightness(level: lowBrightnessLevel)
            } else {
                brightnessControl.restoreBrightness()
            }
        }

        NotificationCenter.default.post(name: .appModelStateChanged, object: nil)
    }

    func setTestBrightness(_ value: Float) {
        testBrightness = value
        brightnessControl.setCustomBrightness(level: value)
    }

    func increaseAutoLockDuration() {
        guard let currentIndex = nearestAutoLockDurationPresetIndex(),
              currentIndex < autoLockDurationPresets.count - 1 else { return }
        autoLockDuration = autoLockDurationPresets[currentIndex + 1]
    }

    func decreaseAutoLockDuration() {
        guard let currentIndex = nearestAutoLockDurationPresetIndex(),
              currentIndex > 0 else { return }
        autoLockDuration = autoLockDurationPresets[currentIndex - 1]
    }

    func getAutoLockDurationDisplay() -> String {
        durationDisplay(for: autoLockDuration)
    }

    func getAutoLockRemainingDisplay() -> String {
        durationDisplay(for: autoLockRemaining)
    }

    func getAgentAutoLockRemainingDisplay() -> String {
        durationDisplay(for: agentAutoLockRemaining)
    }

    func installAgentHooks() {
        do {
            let helperURL = try agentHookMonitor.ensureHelperScript()
            agentHookInstallSummary = try AgentHookInstaller.installAll(helperURL: helperURL)
            agentHookStatusMessage = agentHookStatusText(for: agentHookInstallSummary)
            agentHookSetupError = nil
            debugLog("Installed agent hooks: \(agentHookInstallSummary.installedSources.joined(separator: ","))", logger: AppLog.agentHooks)
        } catch {
            agentHookSetupError = error.localizedDescription
            AppLog.agentHooks.error("Failed to install agent hooks: \(error.localizedDescription, privacy: .public)")
        }
    }

    func uninstallAgentHooks() {
        do {
            agentHookInstallSummary = try AgentHookInstaller.uninstallAll()
            agentHookStatusMessage = agentHookStatusText(for: agentHookInstallSummary)
            agentHookSetupError = nil
            debugLog("Uninstalled agent hooks", logger: AppLog.agentHooks)
        } catch {
            agentHookSetupError = error.localizedDescription
            AppLog.agentHooks.error("Failed to uninstall agent hooks: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshAgentHookStatus() {
        agentHookInstallSummary = AgentHookInstaller.status()
        agentHookStatusMessage = agentHookStatusText(for: agentHookInstallSummary)
    }

    func resetBrightness() {
        let currentBrightness = brightnessControl.getCurrentBrightness()
        testBrightness = currentBrightness
        debugLog("Reset brightness to \(currentBrightness)", logger: AppLog.appModel)
    }

    private func saveLowBrightnessMode() {
        UserDefaults.standard.set(isLowBrightness, forKey: lowBrightnessKey)
        debugLog("Saved low brightness mode: \(isLowBrightness)", logger: AppLog.appModel)
    }

    private func loadLowBrightnessMode() {
        isLoading = true
        defer { isLoading = false }

        isLowBrightness = UserDefaults.standard.bool(forKey: lowBrightnessKey)
        debugLog("Loaded low brightness mode: \(isLowBrightness)", logger: AppLog.appModel)
    }

    private func saveLowBrightnessLevel() {
        UserDefaults.standard.set(lowBrightnessLevel, forKey: lowBrightnessLevelKey)
        debugLog("Saved low brightness level: \(Int(lowBrightnessLevel * 100))%", logger: AppLog.appModel)
    }

    private func loadLowBrightnessLevel() {
        isLoading = true
        defer { isLoading = false }

        if UserDefaults.standard.object(forKey: lowBrightnessLevelKey) == nil {
            lowBrightnessLevel = 0.0
        } else {
            lowBrightnessLevel = UserDefaults.standard.float(forKey: lowBrightnessLevelKey)
        }
        debugLog("Loaded low brightness level: \(Int(lowBrightnessLevel * 100))%", logger: AppLog.appModel)
    }

    private func applyLaunchAtLoginChange() {
        UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginKey)
        debugLog("Saving launch at login: \(launchAtLogin)", logger: AppLog.appModel)

        guard LaunchAtLoginHelper.setLaunchAtLogin(enabled: launchAtLogin) else {
            isLoading = true
            launchAtLogin = LaunchAtLoginHelper.isLaunchAtLoginEnabled()
            isLoading = false
            launchAtLoginError = "settings.launch_at_login.error".localized
            NotificationCenter.default.post(name: .launchAtLoginFailed, object: nil)
            return
        }

        launchAtLoginError = nil
    }

    private func loadLaunchAtLogin() {
        isLoading = true
        defer { isLoading = false }

        launchAtLogin = LaunchAtLoginHelper.isLaunchAtLoginEnabled()
        UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginKey)
        debugLog("Loaded launch at login from system: \(launchAtLogin)", logger: AppLog.appModel)
    }

    private func saveSkipPermissionPrompts() {
        UserDefaults.standard.set(skipPermissionPrompts, forKey: AccessibilityPermissionManager.skipPermissionPromptsKey)
        debugLog("Saved skip permission prompts (debug): \(skipPermissionPrompts)", logger: AppLog.appModel)
    }

    private func loadSkipPermissionPrompts() {
        isLoading = true
        defer { isLoading = false }

        skipPermissionPrompts = UserDefaults.standard.bool(forKey: AccessibilityPermissionManager.skipPermissionPromptsKey)
        debugLog("Loaded skip permission prompts (debug): \(skipPermissionPrompts)", logger: AppLog.appModel)
    }

    private func startJiggling() {
        jiggler.start()
        if isLowBrightness {
            brightnessControl.setLowestBrightness(level: lowBrightnessLevel)
        }
        scheduleAutoLockTimerIfNeeded()
    }

    private func stopJiggling(cancelTimer: Bool, completion: (() -> Void)? = nil) {
        jiggler.stop()
        if cancelTimer {
            cancelAutoLockTimer()
        }

        if isLowBrightness {
            brightnessControl.restoreBrightness(completion: completion)
        } else {
            completion?()
        }
    }

    private func stopJigglingRestoreBrightnessThenLock(cancelTimer: Bool) {
        guard jiggler.isRunning else {
            debugLog("Skip lock request because jiggler is not running", logger: AppLog.appModel)
            return
        }

        stopJiggling(cancelTimer: cancelTimer) { [weak self] in
            self?.lockScreen()
        }
        NotificationCenter.default.post(name: .appModelStateChanged, object: nil)
    }

    private func startAgentHookMonitoring() {
        agentHookMonitor.start { [weak self] event in
            DispatchQueue.main.async {
                self?.handleAgentHookEvent(event)
            }
        }
    }

    private func handleAgentHookEvent(_ event: AgentHookEvent) {
        switch event.lifecycle {
        case .started, .activity:
            guard upsertActiveAgentSession(event) else { return }

        case .completed:
            removeActiveAgentSession(for: event)
            updateActiveAgentSessionPresentation()
            if agentAutoLockEnabled && activeAgentSessions.isEmpty {
                scheduleAgentAutoLockTimer()
            }

        case .ignored:
            return
        }

        debugLog(
            "Agent hook \(event.source) \(event.eventName) -> \(event.lifecycle.rawValue), active: \(activeAgentSessionCount)",
            logger: AppLog.agentHooks
        )
    }

    private func upsertActiveAgentSession(_ event: AgentHookEvent) -> Bool {
        let duplicateEvents = activeAgentSessions.values.filter {
            $0.sessionDeduplicationKey == event.sessionDeduplicationKey && $0.source != event.source
        }

        if let higherPriorityDuplicate = duplicateEvents.first(where: { $0.sourcePriority > event.sourcePriority }) {
            debugLog(
                "Ignored duplicate agent hook \(event.source) for \(event.sessionDeduplicationKey); keeping \(higherPriorityDuplicate.source)",
                logger: AppLog.agentHooks
            )
            return false
        }

        for duplicate in duplicateEvents {
            activeAgentSessions.removeValue(forKey: duplicate.id)
        }

        activeAgentSessions[event.id] = event
        updateActiveAgentSessionPresentation()
        cancelAgentAutoLockTimer()
        return true
    }

    private func removeActiveAgentSession(for event: AgentHookEvent) {
        activeAgentSessions.removeValue(forKey: event.id)
        activeAgentSessions = activeAgentSessions.filter {
            $0.value.sessionDeduplicationKey != event.sessionDeduplicationKey
        }

        if event.eventName.lowercased() == "stop" || event.eventName.lowercased() == "sessionend" {
            let childPrefix = "\(event.source):\(event.sessionID):"
            activeAgentSessions = activeAgentSessions.filter { !$0.key.hasPrefix(childPrefix) }
        }
    }

    private func updateActiveAgentSessionPresentation() {
        activeAgentSessionCount = activeAgentSessions.count
        activeAgentSessionsList = activeAgentSessions.values.sorted {
            if $0.receivedAt == $1.receivedAt {
                return $0.id < $1.id
            }
            return $0.receivedAt > $1.receivedAt
        }
    }

    private func scheduleAgentAutoLockTimer() {
        agentAutoLockTimer?.invalidate()
        agentAutoLockCountdownTimer?.invalidate()

        let endDate = Date().addingTimeInterval(agentAutoLockDelay)
        agentAutoLockEndDate = endDate
        agentAutoLockRemaining = agentAutoLockDelay

        let lockTimer = Timer(timeInterval: agentAutoLockDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleAgentAutoLockTimerFinished()
            }
        }
        RunLoop.main.add(lockTimer, forMode: .common)
        agentAutoLockTimer = lockTimer

        let countdownTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateAgentAutoLockRemaining()
        }
        RunLoop.main.add(countdownTimer, forMode: .common)
        agentAutoLockCountdownTimer = countdownTimer

        debugLog("Agent auto lock scheduled after idle delay", logger: AppLog.agentHooks)
    }

    private func cancelAgentAutoLockTimer() {
        agentAutoLockTimer?.invalidate()
        agentAutoLockCountdownTimer?.invalidate()
        agentAutoLockTimer = nil
        agentAutoLockCountdownTimer = nil
        agentAutoLockEndDate = nil
        agentAutoLockRemaining = 0
    }

    private func updateAgentAutoLockRemaining() {
        guard let agentAutoLockEndDate else {
            agentAutoLockRemaining = 0
            return
        }

        agentAutoLockRemaining = max(agentAutoLockEndDate.timeIntervalSinceNow, 0)
    }

    private func handleAgentAutoLockTimerFinished() {
        agentAutoLockTimer?.invalidate()
        agentAutoLockCountdownTimer?.invalidate()
        agentAutoLockTimer = nil
        agentAutoLockCountdownTimer = nil
        agentAutoLockEndDate = nil
        agentAutoLockRemaining = 0

        guard agentAutoLockEnabled, activeAgentSessions.isEmpty else {
            debugLog("Agent auto lock cancelled because another agent is active", logger: AppLog.agentHooks)
            return
        }

        stopJigglingRestoreBrightnessThenLock(cancelTimer: true)
    }

    private func scheduleAutoLockTimerIfNeeded() {
        autoLockTimer?.invalidate()
        autoLockCountdownTimer?.invalidate()

        guard autoLockTimerEnabled, jiggler.isRunning else {
            autoLockEndDate = nil
            autoLockRemaining = 0
            return
        }

        let duration = max(autoLockDuration, 60)
        let endDate = Date().addingTimeInterval(duration)
        autoLockEndDate = endDate
        autoLockRemaining = duration

        let lockTimer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleAutoLockTimerFinished()
            }
        }
        RunLoop.main.add(lockTimer, forMode: .common)
        autoLockTimer = lockTimer

        let countdownTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateAutoLockRemaining()
        }
        RunLoop.main.add(countdownTimer, forMode: .common)
        autoLockCountdownTimer = countdownTimer

        debugLog("Auto lock timer scheduled for \(Int(duration))s", logger: AppLog.appModel)
    }

    private func cancelAutoLockTimer() {
        autoLockTimer?.invalidate()
        autoLockCountdownTimer?.invalidate()
        autoLockTimer = nil
        autoLockCountdownTimer = nil
        autoLockEndDate = nil
        autoLockRemaining = 0
    }

    private func updateAutoLockRemaining() {
        guard let autoLockEndDate else {
            autoLockRemaining = 0
            return
        }

        autoLockRemaining = max(autoLockEndDate.timeIntervalSinceNow, 0)
    }

    private func handleAutoLockTimerFinished() {
        autoLockTimer?.invalidate()
        autoLockCountdownTimer?.invalidate()
        autoLockTimer = nil
        autoLockCountdownTimer = nil
        autoLockEndDate = nil
        autoLockRemaining = 0

        guard jiggler.isRunning else { return }

        stopJiggling(cancelTimer: false) { [weak self] in
            self?.lockScreen()
        }
        NotificationCenter.default.post(name: .appModelStateChanged, object: nil)
    }

    private func lockScreen() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
        task.arguments = ["-suspend"]

        do {
            try task.run()
            debugLog("Requested lock screen after auto lock timer", logger: AppLog.appModel)
        } catch {
            AppLog.appModel.error("Failed to lock screen: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func nearestAutoLockDurationPresetIndex() -> Int? {
        autoLockDurationPresets.enumerated().min {
            abs($0.element - autoLockDuration) < abs($1.element - autoLockDuration)
        }?.offset
    }

    private func durationDisplay(for duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        if seconds < 60 {
            return "\(seconds) s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours) h"
        }
        return "\(hours) h \(remainingMinutes) min"
    }

    private func saveAutoLockTimerEnabled() {
        UserDefaults.standard.set(autoLockTimerEnabled, forKey: autoLockTimerEnabledKey)
        debugLog("Saved auto lock timer enabled: \(autoLockTimerEnabled)", logger: AppLog.appModel)
    }

    private func saveAutoLockDuration() {
        UserDefaults.standard.set(autoLockDuration, forKey: autoLockDurationKey)
        debugLog("Saved auto lock duration: \(Int(autoLockDuration))s", logger: AppLog.appModel)
    }

    private func loadAutoLockTimerSettings() {
        isLoading = true
        defer { isLoading = false }

        autoLockTimerEnabled = UserDefaults.standard.bool(forKey: autoLockTimerEnabledKey)

        let savedDuration = UserDefaults.standard.double(forKey: autoLockDurationKey)
        if savedDuration > 0 {
            autoLockDuration = savedDuration
        } else {
            autoLockDuration = 30 * 60
        }
        debugLog("Loaded auto lock timer: \(autoLockTimerEnabled), duration: \(Int(autoLockDuration))s", logger: AppLog.appModel)
    }

    private func saveAgentAutoLockEnabled() {
        UserDefaults.standard.set(agentAutoLockEnabled, forKey: agentAutoLockEnabledKey)
        debugLog("Saved agent auto lock enabled: \(agentAutoLockEnabled)", logger: AppLog.agentHooks)
    }

    private func loadAgentAutoLockSettings() {
        isLoading = true
        defer { isLoading = false }

        agentAutoLockEnabled = UserDefaults.standard.bool(forKey: agentAutoLockEnabledKey)
        debugLog("Loaded agent auto lock enabled: \(agentAutoLockEnabled)", logger: AppLog.agentHooks)
    }

    private func agentHookStatusText(for summary: AgentHookInstallSummary) -> String {
        if summary.installedCount == summary.supportedCount {
            return "agent.hooks.status.all_installed".localized
        }

        if summary.installedCount > 0 {
            return String(
                format: "agent.hooks.status.partial".localized,
                summary.installedCount,
                summary.supportedCount
            )
        }

        return "agent.hooks.status.not_installed".localized
    }
}
