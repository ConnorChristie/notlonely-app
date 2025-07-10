import SwiftUI

@main
struct NotLonelyApp: App {
    @StateObject private var voiceLoop = VoiceLoop()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(voiceLoop)
        }
    }
} 