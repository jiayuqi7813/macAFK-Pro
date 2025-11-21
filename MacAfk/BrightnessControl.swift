import Foundation
import AppKit
import CoreGraphics
import Combine

/// 亮度控制类 - 双模式实现
/// 模式1：DisplayServices API（真实硬件亮度，需禁用沙盒）
/// 模式2：Gamma 调光（软件模拟，App Store 兼容）
/// 参考：MonitorControl 和 MonitorControl Lite
class BrightnessControl: ObservableObject {
    
    private var previousBrightness: Float = 0.5
    private let displayQueue: DispatchQueue
    
    // DisplayServices 函数指针（模式1）
    private var setDisplayBrightness: ((CGDirectDisplayID, Float) -> Int32)?
    private var getDisplayBrightness: ((CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)?
    
    // Gamma 表（模式2 - App Store 兼容）
    private var defaultGammaTableRed: [CGGammaValue] = []
    private var defaultGammaTableGreen: [CGGammaValue] = []
    private var defaultGammaTableBlue: [CGGammaValue] = []
    
    // 当前使用的模式
    private var useHardwareBrightness: Bool = false
    
    init() {
        self.displayQueue = DispatchQueue(label: "com.macafk.brightness")
        self.loadDisplayServices()
        self.loadDefaultGammaTables()
    }
    
    /// 动态加载 DisplayServices 框架（模式1）
    private func loadDisplayServices() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/A/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            print("ℹ️ [亮度控制] DisplayServices 不可用，将使用 Gamma 模式（App Store 兼容）")
            return
        }
        
        if let setPtr = dlsym(handle, "DisplayServicesSetBrightness") {
            typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
            self.setDisplayBrightness = unsafeBitCast(setPtr, to: SetBrightnessFunc.self)
        }
        
        if let getPtr = dlsym(handle, "DisplayServicesGetBrightness") {
            typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
            self.getDisplayBrightness = unsafeBitCast(getPtr, to: GetBrightnessFunc.self)
        }
        
        // 检测是否成功加载
        if self.setDisplayBrightness != nil && self.getDisplayBrightness != nil {
            self.useHardwareBrightness = true
            print("✅ [亮度控制] 使用 DisplayServices（真实硬件亮度）")
        } else {
            print("ℹ️ [亮度控制] DisplayServices 加载失败，使用 Gamma 模式")
        }
    }
    
    /// 加载默认 Gamma 表（模式2 - 参考 MonitorControl Lite）
    private func loadDefaultGammaTables() {
        let displayID = CGMainDisplayID()
        var sampleCount: UInt32 = 0
        
        // 获取当前 Gamma 表大小
        CGGetDisplayTransferByTable(displayID, 0, nil, nil, nil, &sampleCount)
        
        if sampleCount == 0 {
            sampleCount = 256 // 默认值
        }
        
        // 读取当前 Gamma 表
        var red = [CGGammaValue](repeating: 0, count: Int(sampleCount))
        var green = [CGGammaValue](repeating: 0, count: Int(sampleCount))
        var blue = [CGGammaValue](repeating: 0, count: Int(sampleCount))
        
        CGGetDisplayTransferByTable(displayID, sampleCount, &red, &green, &blue, &sampleCount)
        
        // 保存原始表
        self.defaultGammaTableRed = red
        self.defaultGammaTableGreen = green
        self.defaultGammaTableBlue = blue
        
        print("ℹ️ [亮度控制] Gamma 表已加载（\(sampleCount) 个采样点）")
    }
    
    // MARK: - Public Methods
    
    func setLowestBrightness() {
        previousBrightness = getAppleBrightness()
        setAppleBrightness(value: 0.01)
    }
    
    func restoreBrightness() {
        setAppleBrightness(value: previousBrightness)
    }
    
    /// 直接设置亮度（用于测试和手动调节）
    func setCustomBrightness(level: Float) {
        setAppleBrightness(value: level)
    }
    
    /// 获取当前亮度
    func getCurrentBrightness() -> Float {
        return getAppleBrightness()
    }
    
    // MARK: - Private Methods
    
    /// 获取 Apple 显示器亮度
    private func getAppleBrightness() -> Float {
        // 模式1：硬件亮度
        if useHardwareBrightness, let getBrightness = self.getDisplayBrightness {
            var brightness: Float = 0.5
            getBrightness(CGMainDisplayID(), &brightness)
            return brightness
        }
        
        // 模式2：Gamma 模式无法准确读取，返回上次设置的值
        return previousBrightness
    }
    
    /// 设置 Apple 显示器亮度
    private func setAppleBrightness(value: Float) {
        let clampedValue = max(min(value, 1.0), 0.0)
        
        self.displayQueue.sync {
            if self.useHardwareBrightness, let setBrightness = self.setDisplayBrightness {
                // 模式1：真实硬件亮度（DisplayServices）
                _ = setBrightness(CGMainDisplayID(), clampedValue)
            } else {
                // 模式2：Gamma 调光（App Store 兼容，参考 MonitorControl Lite）
                self.setGammaBrightness(clampedValue)
            }
        }
    }
    
    /// 使用 Gamma 表调节亮度（App Store 兼容方案）
    /// 参考：MonitorControl Lite 实现
    private func setGammaBrightness(_ brightness: Float) {
        let displayID = CGMainDisplayID()
        
        // 将原始 Gamma 表的每个值乘以亮度系数
        let gammaTableRed = self.defaultGammaTableRed.map { $0 * brightness }
        let gammaTableGreen = self.defaultGammaTableGreen.map { $0 * brightness }
        let gammaTableBlue = self.defaultGammaTableBlue.map { $0 * brightness }
        
        // 应用调整后的 Gamma 表
        let sampleCount = UInt32(gammaTableRed.count)
        CGSetDisplayTransferByTable(displayID, sampleCount, gammaTableRed, gammaTableGreen, gammaTableBlue)
    }
}

