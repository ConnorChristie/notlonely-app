import SwiftUI

struct ContentView: View {
    @EnvironmentObject var voiceLoop: VoiceLoop

    var body: some View {
        NavigationView {
            VStack {
                Toggle("Listening", isOn: $voiceLoop.isListening)
                    .padding()
                ChatView()
            }
            .navigationTitle("Not Lonely")
            .navigationBarItems(trailing:
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gear")
                }
            )
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(VoiceLoop())
    }
} 