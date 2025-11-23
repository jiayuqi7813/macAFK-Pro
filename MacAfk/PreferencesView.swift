import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showRestartAlert = false
    @State private var previewBrightness: Float = 0.0
    @State private var isPreviewing = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("menu.preferences".localized)
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
            
            // 设置内容
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 低亮度设置
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sun.max.fill")
                                .foregroundColor(.orange)
                                .font(.title3)
                            
                            Text("settings.low_brightness".localized)
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(alignment: .leading, spacing: 16) {
                            // 亮度值显示
                            HStack {
                                Text("settings.brightness_level".localized)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Text("\(Int(appModel.lowBrightnessLevel * 100))%")
                                    .foregroundColor(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            // 亮度滑块
                            VStack(alignment: .leading, spacing: 8) {
                                Slider(value: Binding(
                                    get: { appModel.lowBrightnessLevel },
                                    set: { newValue in
                                        appModel.lowBrightnessLevel = newValue
                                        if isPreviewing {
                                            previewBrightness = newValue
                                            appModel.brightnessControl.setCustomBrightness(level: newValue)
                                        }
                                    }
                                ), in: 0...1)
                                .accentColor(.orange)
                                
                                HStack {
                                    Text("0%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("100%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // 预览按钮
                            HStack(spacing: 12) {
                                Button {
                                    if isPreviewing {
                                        // 停止预览，恢复亮度
                                        appModel.brightnessControl.restoreBrightness()
                                        isPreviewing = false
                                    } else {
                                        // 开始预览
                                        previewBrightness = appModel.lowBrightnessLevel
                                        appModel.brightnessControl.setLowestBrightness(level: appModel.lowBrightnessLevel)
                                        isPreviewing = true
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: isPreviewing ? "eye.slash.fill" : "eye.fill")
                                        Text(isPreviewing ? "settings.stop_preview".localized : "settings.preview_brightness".localized)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                
                                if isPreviewing {
                                    Button {
                                        appModel.brightnessControl.restoreBrightness()
                                        isPreviewing = false
                                    } label: {
                                        Text("settings.restore_brightness".localized)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                }
                            }
                            
                            Text("settings.brightness_preview_hint".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 32)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    
                    // 语言设置
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            Text("menu.language".localized)
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(AppLanguage.allCases, id: \.self) { language in
                                Button(action: {
                                    if languageManager.currentLanguage != language {
                                        languageManager.setLanguage(language)
                                        showRestartAlert = true
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: languageManager.currentLanguage == language ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(languageManager.currentLanguage == language ? .blue : .secondary)
                                        
                                        Text(language.localizedDisplayName)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(languageManager.currentLanguage == language ? Color.blue.opacity(0.1) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 32)
                        
                        Text("menu.language.restart_required".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 32)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
                .padding()
            }
            
            Divider()
            
            // 底部按钮
            HStack {
                Spacer()
                
                Button("button.done".localized) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 500, height: 550)
        .onDisappear {
            // 窗口关闭时，如果正在预览，恢复亮度
            if isPreviewing {
                appModel.brightnessControl.restoreBrightness()
                isPreviewing = false
            }
        }
        .onAppear {
            previewBrightness = appModel.lowBrightnessLevel
        }
        .alert("menu.language.restart_required".localized, isPresented: $showRestartAlert) {
            Button("button.done".localized) {
                showRestartAlert = false
            }
        } message: {
            Text("menu.language.restart_required".localized)
        }
    }
}

