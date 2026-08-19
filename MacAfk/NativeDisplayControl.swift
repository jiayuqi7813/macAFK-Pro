//  NativeDisplayControl.swift
//  外接显示器原生亮度控制：三层路由
//    L1 系统原生亮度（DisplayServices，覆盖 Apple 生态外接屏）
//    L2 DDC/CI 硬件背光（Arm64DDC，覆盖大多数第三方外接屏）
//    L3 遮罩窗口软件调暗（公开 AppKit，兜底覆盖一切）

import AppKit
import Combine
import CoreGraphics
import Foundation
import os

/// 单台外接显示器的控制路由结果
struct NativeExternalDisplay: Identifiable {
    enum Method: String {
        case systemNative
        case ddc
        case softwareDimming

        var localizedKey: String {
            switch self {
            case .systemNative: return "native_display.method.system"
            case .ddc: return "native_display.method.ddc"
            case .softwareDimming: return "native_display.method.shade"
            }
        }
    }

    let displayID: CGDirectDisplayID
    let name: String
    let method: Method
    var ddcMaxValue: UInt16?

    var id: CGDirectDisplayID { displayID }
}

/// 外接显示器原生控制器。DDC 操作在内部串行队列执行，遮罩窗口在主线程管理。
final class NativeDisplayControl: ObservableObject {
    @Published private(set) var displays: [NativeExternalDisplay] = []

    private let queue = DispatchQueue(label: "com.macafk.native-display")
    private var ddcServices: [CGDirectDisplayID: Arm64DDC.MatchedService] = [:]
    private var cachedDDCValues: [CGDirectDisplayID: (current: UInt16, max: UInt16)] = [:]
    private var lastWrittenDDCValues: [CGDirectDisplayID: UInt16] = [:]
    private var cachedNativeBrightness: [CGDirectDisplayID: Float] = [:]
    private var lastSoftwareDimLevel: [CGDirectDisplayID: Float] = [:]

    // 写请求合并：排队期间新目标值覆盖旧值，队列任务只写最新值
    private let pendingLock = NSLock()
    private var pendingDDCTargets: [CGDirectDisplayID: (target: UInt16, level: Float)] = [:]

    // DDC 屏低亮度段的 gamma 叠加（与 BetterDisplay 的组合调暗方式一致）
    private var savedGamma: [CGDirectDisplayID: (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue], count: UInt32)] = [:]

    private let pendingRestoreKey = "nativeDDCPendingRestore"

    // DisplayServices（L1，与 BrightnessControl 的内建屏路径同一框架）
    private typealias DSGetFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias HDRCheckFunc = @convention(c) (CGDirectDisplayID) -> Bool
    private var dsGetBrightness: DSGetFunc?
    private var dsSetBrightness: DSSetFunc?
    private var cgsIsHDRSupported: HDRCheckFunc?
    private var cgsIsHDREnabled: HDRCheckFunc?

    init() {
        loadSymbols()
        restorePendingDDCValues()
    }

    private func loadSymbols() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/A/DisplayServices", RTLD_LAZY) {
            if let p = dlsym(handle, "DisplayServicesGetBrightness") {
                dsGetBrightness = unsafeBitCast(p, to: DSGetFunc.self)
            }
            if let p = dlsym(handle, "DisplayServicesSetBrightness") {
                dsSetBrightness = unsafeBitCast(p, to: DSSetFunc.self)
            }
        }
        if let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_LAZY) {
            if let p = dlsym(handle, "CGSIsHDRSupported") {
                cgsIsHDRSupported = unsafeBitCast(p, to: HDRCheckFunc.self)
            }
            if let p = dlsym(handle, "CGSIsHDREnabled") {
                cgsIsHDREnabled = unsafeBitCast(p, to: HDRCheckFunc.self)
            }
        }
    }

    // MARK: - 检测与路由

    /// 枚举外接显示器并确定各自的控制方法
    func detectDisplays() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                self?.performDetect()
                continuation.resume()
            }
        }
    }

    private func performDetect() {
        var result: [NativeExternalDisplay] = []
        let allIDs = Self.onlineDisplays()
        let externalIDs = allIDs.filter { CGDisplayIsBuiltin($0) == 0 }
        debugLog("Native: detecting \(allIDs.count) display(s) (\(externalIDs.count) external), DDC available: \(DDCPrivateAPI.shared.isAvailable)", logger: AppLog.brightness)

        // 释放旧的 DDC 服务引用
        for (_, svc) in ddcServices {
            Arm64DDC.releaseService(svc.service)
        }
        ddcServices.removeAll()

        // 虚拟屏与需要 DDC 的屏分组
        var candidatesForDDC: [CGDirectDisplayID] = []
        var routed: [CGDirectDisplayID: NativeExternalDisplay.Method] = [:]
        for displayID in externalIDs {
            let resolved = Self.resolveMirror(displayID)
            if isVirtualDisplay(resolved) {
                routed[displayID] = .softwareDimming
            } else if supportsSystemNativeBrightness(resolved) {
                routed[displayID] = .systemNative
            } else {
                candidatesForDDC.append(displayID)
            }
        }

        // DDC 匹配 + 试读
        if !candidatesForDDC.isEmpty {
            let matches = Arm64DDC.getServiceMatches(displayIDs: candidatesForDDC.map { Self.resolveMirror($0) })
            var matchByID: [CGDirectDisplayID: Arm64DDC.MatchedService] = [:]
            for m in matches {
                matchByID[m.displayID] = m
            }
            for displayID in candidatesForDDC {
                let resolved = Self.resolveMirror(displayID)
                if let match = matchByID[resolved],
                   let values = Arm64DDC.read(service: match.service, chipAddress: match.chipAddress, command: 0x10), values.max > 0 {
                    ddcServices[displayID] = match
                    cachedDDCValues[displayID] = values
                    saveGammaIfNeeded(displayID)
                    routed[displayID] = .ddc
                    debugLog("Native: display \(displayID) -> DDC (\(match.productName), score \(match.matchScore), current \(values.current)/\(values.max))", logger: AppLog.brightness)
                } else {
                    if let match = matchByID[resolved] {
                        Arm64DDC.releaseService(match.service)
                    }
                    routed[displayID] = .softwareDimming
                    debugLog("Native: display \(displayID) -> software dimming fallback", logger: AppLog.brightness)
                }
            }
            // 释放匹配了但不属于任何候选屏的服务
            let used = Set(ddcServices.values.map { UInt(bitPattern: $0.service) })
            for m in matches where !used.contains(UInt(bitPattern: m.service)) && matchByID[m.displayID] == nil {
                Arm64DDC.releaseService(m.service)
            }
        }

        for displayID in allIDs {
            if CGDisplayIsBuiltin(displayID) != 0 {
                result.append(NativeExternalDisplay(displayID: displayID, name: Self.displayName(displayID), method: .systemNative))
                continue
            }
            let method = routed[displayID] ?? .softwareDimming
            var display = NativeExternalDisplay(displayID: displayID, name: Self.displayName(displayID), method: method)
            if method == .ddc {
                display.ddcMaxValue = cachedDDCValues[displayID]?.max
            }
            result.append(display)
        }

        DispatchQueue.main.async {
            self.displays = result
        }
    }

    /// L1 检测：试读 + 第三方 HDR 屏例外分支（照 MonitorControl isAppleDisplay）
    private func supportsSystemNativeBrightness(_ displayID: CGDirectDisplayID) -> Bool {
        guard let getFn = dsGetBrightness else { return false }
        if CGDisplayVendorNumber(displayID) != 0x610,
           cgsIsHDRSupported?(displayID) == true, cgsIsHDREnabled?(displayID) == true {
            return CGDisplayIsBuiltin(displayID) != 0
        }
        var brightness: Float = -1
        return getFn(displayID, &brightness) == 0 && brightness >= 0
    }

    private func isVirtualDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        guard let dict = DDCPrivateAPI.shared.displayInfo(for: displayID) else { return true }
        if (dict["kCGDisplayIsVirtualDevice"] as? Bool) == true { return true }
        if (dict["kCGDisplayIsAirPlay"] as? Bool) == true { return true }
        return false
    }

    // MARK: - 亮度控制（level 为 0-1 归一化值）

    /// 记录当前亮度，供之后恢复。返回是否成功记录（软件调暗以 gamma 默认表为原值，恒为成功）。
    func cacheBrightness(_ displayID: CGDirectDisplayID) async -> Bool {
        guard let display = displays.first(where: { $0.displayID == displayID }) else { return false }
        switch display.method {
        case .systemNative:
            let resolved = Self.resolveMirror(displayID)
            var brightness: Float = -1
            if let getFn = dsGetBrightness, getFn(resolved, &brightness) == 0, brightness >= 0 {
                cachedNativeBrightness[displayID] = brightness
                return true
            }
            return false
        case .ddc:
            return await runOnQueue { [weak self] in
                guard let self, let svc = self.ddcServices[displayID] else { return false }
                if let values = Arm64DDC.read(service: svc.service, chipAddress: svc.chipAddress, command: 0x10) {
                    self.cachedDDCValues[displayID] = values
                    self.savePendingDDCValue(displayID: displayID, values: values)
                    return true
                }
                // 读失败时沿用检测阶段的缓存值
                return self.cachedDDCValues[displayID] != nil
            }
        case .softwareDimming:
            return true
        }
    }

    /// 设置亮度
    @discardableResult
    func setBrightness(_ displayID: CGDirectDisplayID, level: Float) async -> Bool {
        guard let display = displays.first(where: { $0.displayID == displayID }) else { return false }
        let clamped = max(0, min(level, 1))
        switch display.method {
        case .systemNative:
            let resolved = Self.resolveMirror(displayID)
            guard let setFn = dsSetBrightness else { return false }
            return setFn(resolved, clamped) == 0
        case .ddc:
            guard let maxValue = display.ddcMaxValue ?? cachedDDCValues[displayID]?.max, maxValue > 0 else { return false }
            let target = UInt16((Float(maxValue) * clamped).rounded())
            pendingLock.lock()
            pendingDDCTargets[displayID] = (target, clamped)
            pendingLock.unlock()
            return await runOnQueue { [weak self] in
                guard let self else { return false }
                self.pendingLock.lock()
                let pending = self.pendingDDCTargets.removeValue(forKey: displayID)
                self.pendingLock.unlock()
                // 目标值已被后续任务取走时无需重复写
                guard let pending else { return true }
                // 低亮度段叠加 gamma 调暗：背光最低画面仍可见，level 0 时 gamma 压到全黑
                self.setGammaDim(displayID, factor: pending.level < 0.5 ? pending.level / 0.5 : 1)
                if pending.target == self.lastWrittenDDCValues[displayID] { return true }
                guard let svc = self.ddcServices[displayID] else { return false }
                let success = Arm64DDC.write(service: svc.service, chipAddress: svc.chipAddress, command: 0x10, value: pending.target)
                debugLog("Native: DDC write \(pending.target) to display \(displayID) -> \(success)", logger: AppLog.brightness)
                if success {
                    self.lastWrittenDDCValues[displayID] = pending.target
                }
                return success
            }
        case .softwareDimming:
            return await runOnQueue { [weak self] in
                guard let self else { return false }
                debugLog("Native: gamma dim \(clamped) on display \(displayID)", logger: AppLog.brightness)
                self.setGammaDim(displayID, factor: clamped)
                self.lastSoftwareDimLevel[displayID] = clamped
                return true
            }
        }
    }

    /// 恢复此前记录的亮度
    @discardableResult
    func restoreBrightness(_ displayID: CGDirectDisplayID) async -> Bool {
        guard let display = displays.first(where: { $0.displayID == displayID }) else { return false }
        switch display.method {
        case .systemNative:
            guard let cached = cachedNativeBrightness[displayID], let setFn = dsSetBrightness else { return false }
            let resolved = Self.resolveMirror(displayID)
            let success = setFn(resolved, cached) == 0
            if success {
                cachedNativeBrightness.removeValue(forKey: displayID)
            }
            return success
        case .ddc:
            pendingLock.lock()
            pendingDDCTargets.removeValue(forKey: displayID)
            pendingLock.unlock()
            return await runOnQueue { [weak self] in
                guard let self else { return false }
                self.restoreGamma(displayID)
                guard let svc = self.ddcServices[displayID],
                      let cached = self.cachedDDCValues[displayID] else { return false }
                // 恢复前读回校验：当前值已被外部改动时跳过恢复（容忍 ±1）
                if let lastWritten = self.lastWrittenDDCValues[displayID],
                   let now = Arm64DDC.read(service: svc.service, chipAddress: svc.chipAddress, command: 0x10),
                   abs(Int(now.current) - Int(lastWritten)) > 1 {
                    debugLog("Native: display \(displayID) brightness changed externally (\(now.current) != \(lastWritten)), skip restore", logger: AppLog.brightness)
                    self.clearPendingDDCValue(displayID: displayID)
                    return true
                }
                let success = Arm64DDC.write(service: svc.service, chipAddress: svc.chipAddress, command: 0x10, value: cached.current)
                if success {
                    self.lastWrittenDDCValues.removeValue(forKey: displayID)
                    self.clearPendingDDCValue(displayID: displayID)
                }
                return success
            }
        case .softwareDimming:
            return await runOnQueue { [weak self] in
                guard let self else { return false }
                self.restoreGamma(displayID)
                self.lastSoftwareDimLevel.removeValue(forKey: displayID)
                return true
            }
        }
    }

    /// 读取当前亮度（0-1），读不到返回 nil
    func readBrightness(_ displayID: CGDirectDisplayID) async -> Float? {
        guard let display = displays.first(where: { $0.displayID == displayID }) else { return nil }
        switch display.method {
        case .systemNative:
            let resolved = Self.resolveMirror(displayID)
            var brightness: Float = -1
            if let getFn = dsGetBrightness, getFn(resolved, &brightness) == 0, brightness >= 0 {
                return brightness
            }
            return nil
        case .ddc:
            return await runOnQueue { [weak self] in
                guard let self, let svc = self.ddcServices[displayID],
                      let values = Arm64DDC.read(service: svc.service, chipAddress: svc.chipAddress, command: 0x10), values.max > 0 else { return nil }
                // 只读不更新 cachedDDCValues：那是恢复用的原值缓存，
                // 抖动期间读取会把原值污染成压暗后的值
                return Float(values.current) / Float(values.max)
            }
        case .softwareDimming:
            return await runOnQueue { [weak self] in
                self?.lastSoftwareDimLevel[displayID] ?? 1
            }
        }
    }

    // MARK: - Gamma 调暗（DDC 屏低亮度段叠加；进程退出时 WindowServer 自动恢复 gamma）

    private func saveGammaIfNeeded(_ displayID: CGDirectDisplayID) {
        guard savedGamma[displayID] == nil else { return }
        var r = [CGGammaValue](repeating: 0, count: 4096)
        var g = r
        var b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayID, 4096, &r, &g, &b, &count) == .success, count > 0 else { return }
        let n = Int(count)
        savedGamma[displayID] = (Array(r.prefix(n)), Array(g.prefix(n)), Array(b.prefix(n)), count)
    }

    /// factor 1 = 无调暗（恢复默认表），0 = 全黑
    private func setGammaDim(_ displayID: CGDirectDisplayID, factor: Float) {
        saveGammaIfNeeded(displayID)
        guard let saved = savedGamma[displayID] else { return }
        if factor >= 0.999 {
            CGSetDisplayTransferByTable(displayID, saved.count, saved.r, saved.g, saved.b)
            return
        }
        let f = CGGammaValue(max(0, factor))
        CGSetDisplayTransferByTable(displayID, saved.count, saved.r.map { $0 * f }, saved.g.map { $0 * f }, saved.b.map { $0 * f })
    }

    private func restoreGamma(_ displayID: CGDirectDisplayID) {
        guard let saved = savedGamma[displayID] else { return }
        CGSetDisplayTransferByTable(displayID, saved.count, saved.r, saved.g, saved.b)
    }

    // MARK: - DDC 原值持久化（进程异常退出后的补恢复）

    private func savePendingDDCValue(displayID: CGDirectDisplayID, values: (current: UInt16, max: UInt16)) {
        var pending = UserDefaults.standard.dictionary(forKey: pendingRestoreKey) as? [String: [Int]] ?? [:]
        pending[String(displayID)] = [Int(values.current), Int(values.max)]
        UserDefaults.standard.set(pending, forKey: pendingRestoreKey)
    }

    private func clearPendingDDCValue(displayID: CGDirectDisplayID) {
        var pending = UserDefaults.standard.dictionary(forKey: pendingRestoreKey) as? [String: [Int]] ?? [:]
        pending.removeValue(forKey: String(displayID))
        if pending.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
        } else {
            UserDefaults.standard.set(pending, forKey: pendingRestoreKey)
        }
    }

    private func restorePendingDDCValues() {
        guard let pending = UserDefaults.standard.dictionary(forKey: pendingRestoreKey) as? [String: [Int]], !pending.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let online = Set(Self.onlineDisplays())
            let matches = Arm64DDC.getServiceMatches(displayIDs: Array(online).filter { CGDisplayIsBuiltin($0) == 0 })
            for (key, values) in pending {
                guard let displayID = CGDirectDisplayID(key), values.count == 2, online.contains(displayID),
                      let match = matches.first(where: { $0.displayID == displayID }) else { continue }
                if Arm64DDC.write(service: match.service, chipAddress: match.chipAddress, command: 0x10, value: UInt16(values[0])) {
                    debugLog("Native: restored leftover brightness \(values[0]) for display \(displayID)", logger: AppLog.brightness)
                }
            }
            for m in matches {
                Arm64DDC.releaseService(m.service)
            }
            UserDefaults.standard.removeObject(forKey: self.pendingRestoreKey)
        }
    }

    // MARK: - 工具

    private func runOnQueue<T>(_ block: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: block())
            }
        }
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private static func resolveMirror(_ displayID: CGDirectDisplayID) -> CGDirectDisplayID {
        let mirrored = CGDisplayMirrorsDisplay(displayID)
        return mirrored == kCGNullDirectDisplay ? displayID : mirrored
    }

    private static func displayName(_ displayID: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }) {
            return screen.localizedName
        }
        if let dict = DDCPrivateAPI.shared.displayInfo(for: displayID),
           let names = dict["DisplayProductName"] as? [String: String],
           let name = names["en_US"] ?? names.first?.value {
            return name
        }
        return "Display \(displayID)"
    }
}
