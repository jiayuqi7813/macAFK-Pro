import Foundation
import Combine
import AppKit
import os

/// BetterDisplay 通知请求数据结构
struct IntegrationNotificationRequestData: Codable {
    var uuid: String?
    var commands: [String] = []
    var parameters: [String: String?] = [:]
}

/// BetterDisplay 通知响应数据结构
struct IntegrationNotificationResponseData: Codable {
    var uuid: String?
    var result: Bool?
    var payload: String?
}

/// BetterDisplay 显示器信息
struct BetterDisplayInfo: Codable, Identifiable {
    let UUID: String?
    let alphanumericSerial: String?
    let deviceType: String
    let displayID: String?
    let model: String?
    let name: String
    let originalName: String?
    let productName: String?
    let registryLocation: String?
    let serial: String?
    let tagID: String
    let vendor: String?
    let weekOfManufacture: String?
    let yearOfManufacture: String?

    var id: String { UUID ?? tagID }

    var isDisplayGroup: Bool {
        deviceType == "DisplayGroup"
    }

    var isPhysicalDisplay: Bool {
        deviceType == "Display"
    }
}

/// BetterDisplay 集成管理器
class BetterDisplayManager: ObservableObject {
    static let shared = BetterDisplayManager()

    @Published var isInstalled: Bool = false
    @Published var isRunning: Bool = false
    @Published var isEnabled: Bool = false
    @Published var displays: [BetterDisplayInfo] = []

    private let appPath = "/Applications/BetterDisplay.app"
    private let appBundleIdentifier = "me.waydabber.BetterDisplay"
    private let requestNotificationName = "com.betterdisplay.BetterDisplay.request"
    private let responseNotificationName = "com.betterdisplay.BetterDisplay.response"
    private let userDefaultsKey = "useBetterDisplay"
    private let defaultRequestTimeout: TimeInterval = 5.0

    private var responseObserver: Any?
    private var pendingRequests: [String: (Bool, String?) -> Void] = [:]
    private var cachedBrightness: [String: Float] = [:]

    private init() {
        setupNotificationObserver()
        checkInstallation()
        checkIfRunning()
        loadEnabledState()

        if isInstalled && isRunning && isEnabled {
            refreshDisplays()
        }
    }

    deinit {
        if let observer = responseObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    private func setupNotificationObserver() {
        responseObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(responseNotificationName),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleResponse(notification)
        }
    }

    private func handleResponse(_ notification: Notification) {
        guard let jsonString = notification.object as? String,
              let jsonData = jsonString.data(using: .utf8) else {
            return
        }

        do {
            let response = try JSONDecoder().decode(IntegrationNotificationResponseData.self, from: jsonData)

            if let uuid = response.uuid, let completion = pendingRequests.removeValue(forKey: uuid) {
                completion(response.result ?? false, response.payload)
            }
        } catch {
            AppLog.betterDisplay.error("JSON decode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkInstallation() {
        isInstalled = FileManager.default.fileExists(atPath: appPath)
    }

    func checkIfRunning() {
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            if let bundleId = app.bundleIdentifier {
                if bundleId == appBundleIdentifier ||
                    bundleId.contains("BetterDisplay") ||
                    bundleId.hasPrefix("me.waydabber") {
                    isRunning = true
                    return
                }
            }

            if let appName = app.localizedName, appName.contains("BetterDisplay") {
                isRunning = true
                return
            }

            if let url = app.bundleURL, url.path.contains("BetterDisplay.app") {
                isRunning = true
                return
            }
        }

        isRunning = false
    }

    func testConnection(completion: @escaping (Bool) -> Void) {
        checkInstallation()
        checkIfRunning()

        guard isInstalled, isRunning else {
            completion(false)
            return
        }

        sendRequest(
            commands: ["get"],
            parameters: ["identifiers": nil],
            timeout: 3.0
        ) { [weak self] success, _ in
            if success {
                self?.isRunning = true
            }
            completion(success)
        }
    }

    private func sendNotificationRequest(_ requestData: IntegrationNotificationRequestData) {
        do {
            let encodedData = try JSONEncoder().encode(requestData)
            if let jsonString = String(data: encodedData, encoding: .utf8) {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name(requestNotificationName),
                    object: jsonString,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
        } catch {
            AppLog.betterDisplay.error("Request encoding failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 统一请求封装，带超时
    private func sendRequest(
        commands: [String],
        parameters: [String: String?] = [:],
        timeout: TimeInterval? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let requestUUID = UUID().uuidString
        let requestData = IntegrationNotificationRequestData(
            uuid: requestUUID,
            commands: commands,
            parameters: parameters
        )

        var completed = false
        let lock = NSLock()

        pendingRequests[requestUUID] = { success, payload in
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return }
            completed = true
            completion(success, payload)
        }

        let timeoutInterval = timeout ?? defaultRequestTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutInterval) { [weak self] in
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return }
            completed = true
            self?.pendingRequests.removeValue(forKey: requestUUID)
            AppLog.betterDisplay.error("Request timed out after \(timeoutInterval)s")
            completion(false, nil)
        }

        sendNotificationRequest(requestData)
    }

    private func loadEnabledState() {
        isEnabled = UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)

        if enabled && isInstalled {
            refreshDisplays()
        } else {
            displays = []
        }
    }

    func refreshDisplays() {
        guard isInstalled && isRunning else { return }

        sendRequest(
            commands: ["get"],
            parameters: ["identifiers": nil]
        ) { [weak self] success, payload in
            if success, let payload = payload {
                self?.parseDisplaysJSON(payload)
            }
        }
    }

    private func parseDisplaysJSON(_ jsonString: String) {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let decoder = JSONDecoder()

        if let data = trimmed.data(using: .utf8) {
            if let array = try? decoder.decode([BetterDisplayInfo].self, from: data) {
                publishDisplays(array)
                return
            }

            if let single = try? decoder.decode(BetterDisplayInfo.self, from: data) {
                publishDisplays([single])
                return
            }
        }

        let lines = trimmed.split(separator: "\n").map(String.init)
        if lines.count > 1 {
            var parsed: [BetterDisplayInfo] = []
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let item = try? decoder.decode(BetterDisplayInfo.self, from: data) else {
                    continue
                }
                parsed.append(item)
            }
            if !parsed.isEmpty {
                publishDisplays(parsed)
                return
            }
        }

        let wrappedJSON = "[" + trimmed.replacingOccurrences(of: "}{", with: "},{") + "]"
        if let wrappedData = wrappedJSON.data(using: .utf8),
           let allDisplays = try? decoder.decode([BetterDisplayInfo].self, from: wrappedData) {
            publishDisplays(allDisplays)
            return
        }

        AppLog.betterDisplay.error("Unable to parse display JSON payload")
    }

    private func publishDisplays(_ allDisplays: [BetterDisplayInfo]) {
        DispatchQueue.main.async {
            self.displays = allDisplays.filter { $0.isPhysicalDisplay }
        }
    }

    func cacheBrightnessByUUID(uuid: String, completion: @escaping (Float?) -> Void) {
        guard isInstalled && isRunning && isEnabled else {
            completion(nil)
            return
        }

        sendRequest(
            commands: ["get"],
            parameters: [
                "uuid": uuid,
                "feature": "brightness"
            ]
        ) { [weak self] result, payload in
            guard result, let payload = payload else {
                completion(nil)
                return
            }

            if let value = Float(payload.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self?.cachedBrightness[uuid] = value
                completion(value)
            } else {
                completion(nil)
            }
        }
    }

    func setBrightnessByUUID(uuid: String, brightness: Float, completion: @escaping (Bool) -> Void) {
        guard isInstalled && isRunning && isEnabled else {
            completion(false)
            return
        }

        let clampedBrightness = max(0.0, min(1.0, brightness))

        sendRequest(
            commands: ["set"],
            parameters: [
                "uuid": uuid,
                "brightness": String(format: "%.2f", clampedBrightness)
            ]
        ) { result, _ in
            completion(result)
        }
    }

    func restoreCachedBrightnessByUUID(uuid: String, completion: @escaping (Bool) -> Void) {
        guard let cachedValue = cachedBrightness[uuid] else {
            completion(false)
            return
        }

        setBrightnessByUUID(uuid: uuid, brightness: cachedValue, completion: completion)
    }

    func clearCachedBrightness() {
        cachedBrightness.removeAll()
    }
}
