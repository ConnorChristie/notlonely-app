import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var voiceLoop: VoiceLoop

    var body: some View {
        Form {
            Section(header: Text("Privacy")) {
                Toggle("Private Mode", isOn: $voiceLoop.isPrivateModeEnabled)
                Text("When enabled, audio is processed on your device and never leaves your phone.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Backend")) {
                TextField("Backend URL", text: $voiceLoop.backendURLString)
                    .keyboardType(.URL)
            }

            Section(header: Text("AI Personality")) {
                TextEditor(text: $voiceLoop.personalityPrompt)
                    .frame(height: 120)
            }
        }
        .navigationTitle("Settings")
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(VoiceLoop())
    }
} 