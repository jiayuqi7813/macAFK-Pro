import SwiftUI
import AppKit

// swiftui-layout-components: Form + Section；ios-accessibility: 录音态焦点与标签
struct ShortcutRecorderView: View {
    let action: ShortcutAction
    @Binding var isRecording: Bool
    @ObservedObject var shortcutManager: ShortcutManager

    @State private var recordedKeyCode: UInt16?
    @State private var recordedModifiers: NSEvent.ModifierFlags = []
    @State private var eventMonitor: Any?
    @State private var conflictMessage: String?

    var body: some View {
        HStack {
            if isRecording {
                Label("shortcut.editor.recording".localized, systemImage: "keyboard.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: true)

                Button("button.cancel".localized) {
                    stopRecording()
                }
            } else {
                Button(shortcutManager.getShortcutDisplay(for: action)) {
                    isRecording = true
                    startRecording()
                }
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel(action.displayName)
            }
        }
        .onAppear {
            if isRecording {
                startRecording()
            }
        }
        .onDisappear {
            stopRecording()
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                startRecording()
            } else {
                stopRecording()
            }
        }
        .alert("shortcut.editor.conflict.title".localized, isPresented: Binding(
            get: { conflictMessage != nil },
            set: { if !$0 { conflictMessage = nil } }
        )) {
            Button("button.done".localized) {
                conflictMessage = nil
            }
        } message: {
            if let conflictMessage {
                Text(conflictMessage)
            }
        }
    }

    private func startRecording() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.isRecording else { return event }

            self.recordedKeyCode = event.keyCode
            self.recordedModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

            guard !self.recordedModifiers.isEmpty, let keyCode = self.recordedKeyCode else {
                return nil
            }

            if let conflict = self.shortcutManager.updateShortcut(
                for: self.action,
                keyCode: keyCode,
                modifiers: self.recordedModifiers
            ) {
                self.conflictMessage = String(
                    format: "shortcut.editor.conflict.message".localized,
                    conflict.displayName
                )
            } else {
                self.isRecording = false
            }

            return nil
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// swiftui-navigation: NavigationStack 模态表单；swiftui-layout-components: Form
struct ShortcutEditorView: View {
    @ObservedObject var shortcutManager: ShortcutManager
    @Environment(\.dismiss) private var dismiss

    @State private var recordingAction: ShortcutAction?

    var body: some View {
        NavigationStack {
            Form {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    Section {
                        LabeledContent {
                            ShortcutRecorderView(
                                action: action,
                                isRecording: Binding(
                                    get: { recordingAction == action },
                                    set: { isRecording in
                                        recordingAction = isRecording ? action : nil
                                    }
                                ),
                                shortcutManager: shortcutManager
                            )
                        } label: {
                            VStack(alignment: .leading) {
                                Label(action.displayName, systemImage: action.icon)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(action.color)
                                Text(action.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("shortcut.editor.title".localized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("button.reset_defaults".localized) {
                        shortcutManager.resetToDefaults()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("button.done".localized) {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

extension ShortcutAction: CaseIterable {
    static var allCases: [ShortcutAction] {
        [.toggleJiggle, .toggleBrightness, .increaseJiggleInterval, .decreaseJiggleInterval]
    }

    var displayName: String {
        switch self {
        case .toggleJiggle: return "shortcut.toggle_jiggle".localized
        case .toggleBrightness: return "shortcut.toggle_brightness".localized
        case .increaseJiggleInterval: return "shortcut.increase_interval".localized
        case .decreaseJiggleInterval: return "shortcut.decrease_interval".localized
        }
    }

    var description: String {
        switch self {
        case .toggleJiggle: return "shortcut.toggle_jiggle.description".localized
        case .toggleBrightness: return "shortcut.toggle_brightness.description".localized
        case .increaseJiggleInterval: return "shortcut.increase_interval.description".localized
        case .decreaseJiggleInterval: return "shortcut.decrease_interval.description".localized
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
