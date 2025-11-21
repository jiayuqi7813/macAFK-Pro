import SwiftUI

struct SettingsView: View {
    @ObservedObject var appModel: AppModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("MacAfk Settings")
                .font(.headline)
            
            Toggle("Enable Low Brightness Mode", isOn: $appModel.isLowBrightness)
                .help("Automatically lower brightness when Jiggler is active")
            
            Divider()
            
            Text("Shortcuts")
                .font(.subheadline)
            Text("Toggle Jiggler: Cmd + Ctrl + S")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            Button("Quit MacAfk") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
