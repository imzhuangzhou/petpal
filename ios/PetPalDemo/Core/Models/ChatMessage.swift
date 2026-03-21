import Foundation

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let role: Role
    let content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    enum Role: String, Hashable, Sendable {
        case user
        case assistant
    }
}
