import Foundation
import SwiftUI
import Combine

class AppModel: ObservableObject {
    @Published var isJiggling = false
    @Published var isLowBrightness = false
    @Published var testBrightness: Float = 0.5  // 测试用的亮度值（0.0 - 1.0）
    
    // 子对象：使用普通属性 + Combine 订阅
    let jiggler = Jiggler()
    let brightnessControl = BrightnessControl()
    let shortcutManager = ShortcutManager()
    
    // Combine 订阅
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 订阅 jiggler 的变化，转发给 AppModel
        jiggler.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        // 订阅 shortcutManager 的变化，转发给 AppModel
        shortcutManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
        // 设置快捷键回调
        shortcutManager.onAction = { [weak self] action in
            DispatchQueue.main.async {
                self?.handleShortcutAction(action)
            }
        }
        shortcutManager.startListening()
    }
    
    // MARK: - 快捷键动作处理
    
    /// 处理快捷键动作
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
        isJiggling.toggle()
        if isJiggling {
            jiggler.start()
            if isLowBrightness {
                brightnessControl.setLowestBrightness()
            }
        } else {
            jiggler.stop()
            if isLowBrightness {
                brightnessControl.restoreBrightness()
            }
        }
    }
    
    func toggleBrightnessMode() {
        isLowBrightness.toggle()
        // 立即应用亮度变化（如果正在运行）
        if isJiggling {
            if isLowBrightness {
                brightnessControl.setLowestBrightness()
            } else {
                brightnessControl.restoreBrightness()
            }
        }
    }
    
    // MARK: - 低亮度模式切换（支持快捷键）
    
    /// 切换低亮度模式（带通知）
    func toggleBrightnessModeWithNotification() {
        toggleBrightnessMode()
        
        // 可选：显示通知
        let message = isLowBrightness ? "低亮度模式已启用" : "低亮度模式已关闭"
        print("ℹ️ \(message)")
    }
    
    /// 设置测试亮度（用于滑块测试）
    func setTestBrightness(_ value: Float) {
        testBrightness = value
        brightnessControl.setCustomBrightness(level: value)
    }
    
    /// 重置亮度为系统值
    func resetBrightness() {
        let currentBrightness = brightnessControl.getCurrentBrightness()
        testBrightness = currentBrightness
        print("🔄 [AppModel] 重置亮度为: \(currentBrightness)")
    }
}
