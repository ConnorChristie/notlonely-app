import SwiftUI

struct ChatView: View {
    @EnvironmentObject var voiceLoop: VoiceLoop

    var body: some View {
        VStack {
            ScrollView {
                ScrollViewReader { scrollViewProxy in
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(voiceLoop.messages) { message in
                            MessageView(message: message)
                        }
                    }
                    .onChange(of: voiceLoop.messages) { _ in
                        if let lastMessage = voiceLoop.messages.last {
                            withAnimation {
                                scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .layoutPriority(1)

            if voiceLoop.isListening {
                HStack {
                    Text("Listening…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            }
        }
    }
}

struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.sender == .user {
                Spacer()
            }
            Text(message.text)
                .padding(10)
                .foregroundColor(.white)
                .background(message.sender == .user ? Color.blue : Color.gray)
                .cornerRadius(10)
            if message.sender == .assistant {
                Spacer()
            }
        }
        .padding(.horizontal)
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let voiceLoop = VoiceLoop()
        voiceLoop.messages = [
            ChatMessage(text: "Hello there!", sender: .user),
            ChatMessage(text: "Hi! How can I help you today?", sender: .assistant),
            ChatMessage(text: "I was just testing.", sender: .user)
        ]
        return ChatView()
            .environmentObject(voiceLoop)
    }
} 