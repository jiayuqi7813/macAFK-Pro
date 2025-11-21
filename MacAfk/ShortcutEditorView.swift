import SwiftUI
import AppKit

/// 快捷键录制视图
struct ShortcutRecorderView: View {
    let action: ShortcutAction
    @Binding var isRecording: Bool
    @ObservedObject var shortcutManager: ShortcutManager
    
    @State private var recordedKeyCode: UInt16?
    @State private var recordedModifiers: NSEvent.ModifierFlags = []
    
    var body: some View {
        HStack {
            if isRecording {
                HStack {
                    Image(systemName: "keyboard.fill")
                        .foregroundColor(.red)
                    Text("按下新快捷键...")
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red, lineWidth: 2)
                        )
                )
                
                Button("取消") {
                    isRecording = false
                }
                .buttonStyle(.bordered)
            } else {
                Button(shortcutManager.getShortcutDisplay(for: action)) {
                    isRecording = true
                    startRecording()
                }
                .font(.system(.body, design: .monospaced))
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            if isRecording {
                startRecording()
            }
        }
    }
    
    private func startRecording() {
        // 使用本地事件监听器录制快捷键
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.isRecording {
                self.recordedKeyCode = event.keyCode
                self.recordedModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                
                // 至少需要一个修饰键
                if !self.recordedModifiers.isEmpty {
                    self.shortcutManager.updateShortcut(
                        for: self.action,
                        keyCode: self.recordedKeyCode!,
                        modifiers: self.recordedModifiers
                    )
                    self.isRecording = false
                }
                
                return nil // 阻止事件传播
            }
            return event
        }
    }
}

/// 快捷键编辑器主视图
struct ShortcutEditorView: View {
    @ObservedObject var shortcutManager: ShortcutManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var recordingAction: ShortcutAction?
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("快捷键设置")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // 快捷键列表
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(ShortcutAction.allCases, id: \.self) { action in
                        ShortcutEditRow(
                            action: action,
                            shortcutManager: shortcutManager,
                            isRecording: Binding(
                                get: { recordingAction == action },
                                set: { isRecording in
                                    recordingAction = isRecording ? action : nil
                                }
                            )
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // 底部按钮
            HStack {
                Button("恢复默认") {
                    shortcutManager.resetToDefaults()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 500, height: 400)
    }
}

/// 单个快捷键编辑行
struct ShortcutEditRow: View {
    let action: ShortcutAction
    @ObservedObject var shortcutManager: ShortcutManager
    @Binding var isRecording: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // 图标和名称
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .foregroundColor(action.color)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(action.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 快捷键录制
            ShortcutRecorderView(
                action: action,
                isRecording: $isRecording,
                shortcutManager: shortcutManager
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// 扩展 ShortcutAction 添加显示属性
extension ShortcutAction: CaseIterable {
    static var allCases: [ShortcutAction] {
        [.toggleJiggle, .toggleBrightness, .increaseJiggleInterval, .decreaseJiggleInterval]
    }
    
    var displayName: String {
        switch self {
        case .toggleJiggle: return "切换防休眠"
        case .toggleBrightness: return "切换低亮度模式"
        case .increaseJiggleInterval: return "增加抖动间隔"
        case .decreaseJiggleInterval: return "减少抖动间隔"
        }
    }
    
    var description: String {
        switch self {
        case .toggleJiggle: return "开启或关闭鼠标抖动防休眠"
        case .toggleBrightness: return "开启或关闭低亮度模式"
        case .increaseJiggleInterval: return "增加鼠标抖动的时间间隔"
        case .decreaseJiggleInterval: return "减少鼠标抖动的时间间隔"
        }
    }
    
    var icon: String {
        switch self {
        case .toggleJiggle: return "power"
        case .toggleBrightness: return "sun.max"
        case .increaseJiggleInterval: return "arrow.up.circle"
        case .decreaseJiggleInterval: return "arrow.down.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .toggleJiggle: return .green
        case .toggleBrightness: return .orange
        case .increaseJiggleInterval: return .blue
        case .decreaseJiggleInterval: return .purple
        }
    }
}

