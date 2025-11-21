import Foundation
import CoreGraphics
import Combine

class Jiggler: ObservableObject {
    @Published var isRunning = false
    @Published var currentInterval: TimeInterval = 60 // 默认 60 秒
    
    private var timer: Timer?
    
    // 可选的间隔档位（秒）
    private let intervalPresets: [TimeInterval] = [10, 30, 60, 120, 300, 600]
    private var currentPresetIndex: Int = 2 // 默认 60 秒
    
    func start() {
        // 确保在主线程上执行
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
            return
        }
        
        guard !isRunning else {
            print("⚠️ [Jiggler] 已经在运行中")
            return
        }
        
        print("🚀 [Jiggler] 准备启动...")
        isRunning = true
        
        // 使用当前间隔启动定时器（添加到主 RunLoop）
        let newTimer = Timer(timeInterval: currentInterval, repeats: true) { [weak self] _ in
            print("⏰ [Jiggler] Timer 触发")
            self?.jiggleMouse()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        
        // 检查 timer 是否有效
        if timer?.isValid == true {
            print("✅ [Jiggler] Timer 创建成功，间隔: \(Int(currentInterval)) 秒")
        } else {
            print("❌ [Jiggler] Timer 创建失败")
        }
        
        // 立即执行一次
        print("🎯 [Jiggler] 立即执行首次抖动")
        jiggleMouse()
        
        print("▶️ [Jiggler] 已启动，间隔: \(Int(currentInterval)) 秒")
    }
    
    func stop() {
        // 确保在主线程上执行
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stop()
            }
            return
        }
        
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        print("⏸️ [Jiggler] 已停止")
    }
    
    /// 增加抖动间隔
    func increaseInterval() {
        guard currentPresetIndex < intervalPresets.count - 1 else {
            print("⚠️ [Jiggler] 已达到最大间隔")
            return
        }
        
        currentPresetIndex += 1
        currentInterval = intervalPresets[currentPresetIndex]
        
        // 如果正在运行，重启定时器
        if isRunning {
            restart()
        }
        
        print("⬆️ [Jiggler] 间隔增加到 \(Int(currentInterval)) 秒")
    }
    
    /// 减少抖动间隔
    func decreaseInterval() {
        guard currentPresetIndex > 0 else {
            print("⚠️ [Jiggler] 已达到最小间隔")
            return
        }
        
        currentPresetIndex -= 1
        currentInterval = intervalPresets[currentPresetIndex]
        
        // 如果正在运行，重启定时器
        if isRunning {
            restart()
        }
        
        print("⬇️ [Jiggler] 间隔减少到 \(Int(currentInterval)) 秒")
    }
    
    /// 设置自定义间隔
    func setInterval(_ interval: TimeInterval) {
        currentInterval = interval
        
        // 更新档位索引（找最接近的）
        if let closestIndex = intervalPresets.enumerated().min(by: { abs($0.element - interval) < abs($1.element - interval) })?.offset {
            currentPresetIndex = closestIndex
        }
        
        // 如果正在运行，重启定时器
        if isRunning {
            restart()
        }
        
        print("🔧 [Jiggler] 间隔设置为 \(Int(currentInterval)) 秒")
    }
    
    /// 重启定时器（应用新间隔）
    private func restart() {
        stop()
        start()
    }
    
    /// 获取间隔显示字符串
    func getIntervalDisplay() -> String {
        if currentInterval < 60 {
            return "\(Int(currentInterval)) 秒"
        } else {
            let minutes = Int(currentInterval / 60)
            return "\(minutes) 分钟"
        }
    }
    
    private func jiggleMouse() {
        print("🐭 [Jiggler] jiggleMouse() 被调用")
        
        // 获取当前鼠标位置
        guard let currentEvent = CGEvent(source: nil) else {
            print("❌ [Jiggler] 无法创建 CGEvent（可能缺少辅助功能权限）")
            return
        }
        
        let mouseLocation = currentEvent.location
        print("📍 [Jiggler] 当前鼠标位置: (\(mouseLocation.x), \(mouseLocation.y))")
        
        // 向右移动 1 像素
        let newLocation = CGPoint(x: mouseLocation.x + 1, y: mouseLocation.y)
        let moveRight = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: newLocation,
            mouseButton: .left
        )
        
        if moveRight != nil {
            moveRight?.post(tap: .cghidEventTap)
            print("➡️ [Jiggler] 鼠标移动到: (\(newLocation.x), \(newLocation.y))")
        } else {
            print("❌ [Jiggler] 无法创建移动事件")
        }
        
        // 延迟一点再移回（使用 weak self 避免循环引用）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            guard self?.isRunning == true else {
                print("⚠️ [Jiggler] 已停止，跳过移回操作")
                return
            }
            
            let moveBack = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: mouseLocation,
                mouseButton: .left
            )
            
            if moveBack != nil {
                moveBack?.post(tap: .cghidEventTap)
                print("⬅️ [Jiggler] 鼠标移回: (\(mouseLocation.x), \(mouseLocation.y))")
            } else {
                print("❌ [Jiggler] 无法创建移回事件")
            }
        }
    }
}
