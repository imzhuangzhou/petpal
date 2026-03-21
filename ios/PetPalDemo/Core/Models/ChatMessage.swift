import Foundation

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let role: Role
    var content: String
    var relatedEvents: [RelatedEvent]

    init(id: UUID = UUID(), role: Role, content: String, relatedEvents: [RelatedEvent] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.relatedEvents = relatedEvents
    }

    enum Role: String, Hashable, Sendable {
        case user
        case assistant
    }
}
