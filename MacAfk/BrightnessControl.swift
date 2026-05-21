import Foundation
import AppKit
import CoreGraphics
import Combine
import os

enum BrightnessControlIssue: Equatable, Hashable, Identifiable {
    case displayServicesUnavailable
    case betterDisplayNotReady
    case externalDisplayUnmapped(displayID: UInt32)
    case externalBrightnessFailed(displayID: UInt32)
    case builtinBrightnessFailed(displayID: UInt32)

    var id: String {
        switch self {
        case .displayServicesUnavailable:
            return "displayServicesUnavailable"
        case .betterDisplayNotReady:
            return "betterDisplayNotReady"
        case .externalDisplayUnmapped(let displayID):
            return "externalDisplayUnmapped-\(displayID)"
        case .externalBrightnessFailed(let displayID):
            return "externalBrightnessFailed-\(displayID)"
        case .builtinBrightnessFailed(let displayID):
            return "builtinBrightnessFailed-\(displayID)"
        }
    }

    var localizedMessage: String {
        switch self {
        case .displayServicesUnavailable:
            return "brightness.error.display_services".localized
        case .betterDisplayNotReady:
            return "brightness.error.betterdisplay_not_ready".localized
        case .externalDisplayUnmapped(let displayID):
            return String(format: "brightness.error.external_unmapped".localized, Int(displayID))
        case .externalBrightnessFailed(let displayID):
            return String(format: "brightness.error.external_failed".localized, Int(displayID))
        case .builtinBrightnessFailed(let displayID):
            return String(format: "brightness.error.builtin_failed".localized, Int(displayID))
        }
    }
}

/// DisplayServices 私有 API 封装，避免主线程阻塞
private final class DisplayServicesBackend {
    private let queue = DispatchQueue(label: "com.macafk.display-services")
    private var setDisplayBrightness: ((CGDirectDisplayID, Float) -> Int32)?
    private var getDisplayBrightness: ((CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)?
    private(set) var isAvailable = false

    init() {
        loadDisplayServices()
    }

    private func loadDisplayServices() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/A/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            AppLog.brightness.error("Unable to load DisplayServices framework")
            return
        }

        if let setPtr = dlsym(handle, "DisplayServicesSetBrightness") {
            typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
            setDisplayBrightness = unsafeBitCast(setPtr, to: SetBrightnessFunc.self)
        }

        if let getPtr = dlsym(handle, "DisplayServicesGetBrightness") {
            typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
            getDisplayBrightness = unsafeBitCast(getPtr, to: GetBrightnessFunc.self)
        }

        isAvailable = setDisplayBrightness != nil && getDisplayBrightness != nil
        if isAvailable {
            debugLog("DisplayServices loaded", logger: AppLog.brightness)
        } else {
            AppLog.brightness.error("DisplayServices symbols missing")
        }
    }

    func getBrightness(displayID: CGDirectDisplayID) async -> Float? {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self,
                      let getBrightness = self.getDisplayBrightness else {
                    continuation.resume(returning: nil)
                    return
                }

                var brightness: Float = 0.5
                let result = getBrightness(displayID, &brightness)
                continuation.resume(returning: result == 0 ? brightness : nil)
            }
        }
    }

    func setBrightness(displayID: CGDirectDisplayID, value: Float) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self,
                      let setBrightness = self.setDisplayBrightness else {
                    continuation.resume(returning: false)
                    return
                }

                let clampedValue = max(min(value, 1.0), 0.0)
                let result = setBrightness(displayID, clampedValue)
                continuation.resume(returning: result == 0)
            }
        }
    }
}

/// 亮度控制类 - Pro 版本
class BrightnessControl: ObservableObject {
    @Published private(set) var issues: [BrightnessControlIssue] = []

    private var previousBrightnessMap: [CGDirectDisplayID: Float] = [:]
    private let displayBackend = DisplayServicesBackend()
    private let betterDisplayManager = BetterDisplayManager.shared
    private var displayUUIDMapping: [CGDirectDisplayID: String] = [:]

    init() {
        if !displayBackend.isAvailable {
            publishIssues([.displayServicesUnavailable])
        }
        updateDisplayMapping()
    }

    func updateDisplayMapping() {
        displayUUIDMapping.removeAll()

        guard betterDisplayManager.isInstalled && betterDisplayManager.isRunning && betterDisplayManager.isEnabled else {
            debugLog("BetterDisplay not ready, skipping mapping", logger: AppLog.brightness)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self.refreshDisplayMapping()
        }
    }

    private func refreshDisplayMapping() async {
        displayUUIDMapping.removeAll()
        var newIssues: [BrightnessControlIssue] = []

        guard betterDisplayManager.isInstalled && betterDisplayManager.isRunning && betterDisplayManager.isEnabled else {
            newIssues.append(.betterDisplayNotReady)
            publishIssues(newIssues)
            return
        }

        if betterDisplayManager.displays.isEmpty {
            betterDisplayManager.refreshDisplays()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        let cgDisplays = getAllDisplays()
        let bdDisplays = betterDisplayManager.displays

        for cgDisplayID in cgDisplays where CGDisplayIsBuiltin(cgDisplayID) == 0 {
            let cgDisplayIDString = String(cgDisplayID)

            if let bdDisplay = bdDisplays.first(where: { $0.displayID == cgDisplayIDString }),
               let uuid = bdDisplay.UUID {
                displayUUIDMapping[cgDisplayID] = uuid
                debugLog("Mapped CG \(cgDisplayID) -> UUID \(uuid)", logger: AppLog.brightness)
            } else {
                newIssues.append(.externalDisplayUnmapped(displayID: cgDisplayID))
            }
        }

        publishIssues(newIssues)
    }

    func setLowestBrightness(level: Float = 0.0, completion: (() -> Void)? = nil) {
        Task { @MainActor in
            await self.performSetLowestBrightness(level: level)
            completion?()
        }
    }

    private func performSetLowestBrightness(level: Float) async {
        var newIssues = issues.filter {
            if case .externalDisplayUnmapped = $0 { return false }
            if case .externalBrightnessFailed = $0 { return false }
            if case .builtinBrightnessFailed = $0 { return false }
            return true
        }

        let displays = getAllDisplays()
        let externalDisplays = displays.filter { CGDisplayIsBuiltin($0) == 0 }

        if !externalDisplays.isEmpty {
            if displayUUIDMapping.isEmpty || externalDisplays.contains(where: { displayUUIDMapping[$0] == nil }) {
                await refreshDisplayMapping()
            }
        }

        for displayID in displays {
            if CGDisplayIsBuiltin(displayID) != 0 {
                if let brightness = await displayBackend.getBrightness(displayID: displayID) {
                    previousBrightnessMap[displayID] = brightness
                } else if displayBackend.isAvailable {
                    newIssues.append(.builtinBrightnessFailed(displayID: displayID))
                }
            } else if let uuid = displayUUIDMapping[displayID] {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    betterDisplayManager.cacheBrightnessByUUID(uuid: uuid) { _ in
                        continuation.resume()
                    }
                }
            } else {
                newIssues.append(.externalDisplayUnmapped(displayID: displayID))
            }
        }

        publishIssues(newIssues)
        await setAllDisplaysBrightness(value: level)
    }

    func restoreBrightness(completion: (() -> Void)? = nil) {
        Task { @MainActor in
            await self.performRestoreBrightness()
            completion?()
        }
    }

    private func performRestoreBrightness() async {
        let displays = getAllDisplays()

        for displayID in displays {
            if CGDisplayIsBuiltin(displayID) != 0 {
                if let brightness = previousBrightnessMap[displayID] {
                    let success = await displayBackend.setBrightness(displayID: displayID, value: brightness)
                    if !success {
                        var newIssues = issues
                        newIssues.append(.builtinBrightnessFailed(displayID: displayID))
                        publishIssues(newIssues)
                    }
                }
            } else if let uuid = displayUUIDMapping[displayID] {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    betterDisplayManager.restoreCachedBrightnessByUUID(uuid: uuid) { _ in
                        continuation.resume()
                    }
                }
            }
        }
    }

    func setCustomBrightness(level: Float) {
        Task { @MainActor in
            await setAllDisplaysBrightness(value: level)
        }
    }

    func getCurrentBrightness() -> Float {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Float = 0.5

        Task {
            if let brightness = await displayBackend.getBrightness(displayID: CGMainDisplayID()) {
                result = brightness
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 1.0)
        return result
    }

    private func getAllDisplays() -> [CGDirectDisplayID] {
        let maxDisplays: UInt32 = 32
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0

        let result = CGGetOnlineDisplayList(maxDisplays, &displays, &displayCount)

        if result == .success {
            return Array(displays.prefix(Int(displayCount)))
        }
        return [CGMainDisplayID()]
    }

    private func setAllDisplaysBrightness(value: Float) async {
        let displays = getAllDisplays()
        let clampedValue = max(min(value, 1.0), 0.0)
        var newIssues = issues.filter {
            if case .externalBrightnessFailed = $0 { return false }
            if case .builtinBrightnessFailed = $0 { return false }
            return true
        }

        for displayID in displays {
            if CGDisplayIsBuiltin(displayID) != 0 {
                let success = await displayBackend.setBrightness(displayID: displayID, value: clampedValue)
                if !success && displayBackend.isAvailable {
                    newIssues.append(.builtinBrightnessFailed(displayID: displayID))
                }
            } else if let uuid = displayUUIDMapping[displayID] {
                let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    betterDisplayManager.setBrightnessByUUID(uuid: uuid, brightness: clampedValue) { success in
                        continuation.resume(returning: success)
                    }
                }
                if !success {
                    newIssues.append(.externalBrightnessFailed(displayID: displayID))
                }
            } else {
                newIssues.append(.externalDisplayUnmapped(displayID: displayID))
            }
        }

        publishIssues(newIssues)
    }

    private func publishIssues(_ newIssues: [BrightnessControlIssue]) {
        let unique = Array(Set(newIssues))
        issues = unique
    }
}
