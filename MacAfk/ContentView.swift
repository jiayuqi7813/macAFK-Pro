import SwiftUI

// 快捷键显示行组件
struct ShortcutRow: View {
    let icon: String
    let title: String
    let shortcut: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text(shortcut)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.2)))
        }
    }
}

struct ContentView: View {
    @ObservedObject var appModel: AppModel
    @State private var showingShortcutEditor = false
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: appModel.isJiggling ? "sleep.circle.fill" : "sleep")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .foregroundColor(appModel.isJiggling ? .green : .secondary)
                    .symbolEffect(.bounce, value: appModel.isJiggling)
                
                Text("app.name".localized)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(appModel.isJiggling ? "status.preventing_sleep".localized : "status.system_sleep_allowed".localized)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            // Controls
            VStack(spacing: 20) {
                Button(action: {
                    appModel.toggleJiggle()
                }) {
                    Text(appModel.isJiggling ? "button.stop_jiggling".localized : "button.start_jiggling".localized)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(width: 200, height: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(appModel.isJiggling ? .red : .green)
                .controlSize(.large)
                
                // 抖动间隔显示
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                    
                    Text("jiggle.interval".localized)
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Text(appModel.jiggler.getIntervalDisplay())
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .frame(minWidth: 60, alignment: .leading)
                    
                    Spacer()
                    
                    // 间隔调整按钮
                    HStack(spacing: 4) {
                        Button(action: {
                            appModel.jiggler.decreaseInterval()
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                        .help("jiggle.interval.decrease".localized)
                        
                        Button(action: {
                            appModel.jiggler.increaseInterval()
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)
                        .help("jiggle.interval.increase".localized)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                
                Toggle("settings.low_brightness_mode".localized, isOn: $appModel.isLowBrightness)
                    .toggleStyle(.switch)
                    .help("settings.low_brightness_mode.help".localized)
                
                Toggle("settings.launch_at_login".localized, isOn: $appModel.launchAtLogin)
                    .toggleStyle(.switch)
                    .help("settings.launch_at_login.help".localized)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            
            /* 亮度测试区域 - 已注释
            VStack(spacing: 15) {
                HStack {
                    Image(systemName: "light.max")
                        .foregroundColor(.orange)
                    Text("亮度测试")
                        .font(.headline)
                        .fontWeight(.bold)
                    Spacer()
                    Text("\(Int(appModel.testBrightness * 100))%")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                HStack(spacing: 10) {
                    Image(systemName: "sun.min.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Slider(value: $appModel.testBrightness, in: 0.01...1.0)
                        .onChange(of: appModel.testBrightness) { _, newValue in
                            // 实时设置亮度
                            appModel.setTestBrightness(newValue)
                        }
                    
                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                HStack(spacing: 10) {
                    Button("最低") {
                        appModel.testBrightness = 0.01
                        appModel.setTestBrightness(0.01)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("25%") {
                        appModel.testBrightness = 0.25
                        appModel.setTestBrightness(0.25)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("50%") {
                        appModel.testBrightness = 0.5
                        appModel.setTestBrightness(0.5)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("75%") {
                        appModel.testBrightness = 0.75
                        appModel.setTestBrightness(0.75)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("最高") {
                        appModel.testBrightness = 1.0
                        appModel.setTestBrightness(1.0)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Text("💡 拖动滑块或点击按钮测试亮度控制是否工作")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                    )
            )
            */
            
            // 快捷键配置
            VStack(spacing: 15) {
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundColor(.blue)
                    Text("settings.title".localized)
                        .font(.headline)
                        .fontWeight(.bold)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    ShortcutRow(
                        icon: "power",
                        title: "shortcut.toggle_jiggle".localized,
                        shortcut: appModel.shortcutManager.getShortcutDisplay(for: .toggleJiggle),
                        color: .green
                    )
                    
                    ShortcutRow(
                        icon: "sun.max",
                        title: "shortcut.toggle_brightness".localized,
                        shortcut: appModel.shortcutManager.getShortcutDisplay(for: .toggleBrightness),
                        color: .orange
                    )
                }
                
                Button(action: {
                    showingShortcutEditor = true
                }) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("button.customize_all_shortcuts".localized)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    )
            )
            
            // Footer
            Text("footer.permission_hint".localized)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 700)
        .sheet(isPresented: $showingShortcutEditor) {
            ShortcutEditorView(shortcutManager: appModel.shortcutManager)
        }
    }
}
