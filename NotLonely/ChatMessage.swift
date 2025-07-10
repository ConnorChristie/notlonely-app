import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let sender: Sender
}

enum Sender {
    case user
    case assistant
} 