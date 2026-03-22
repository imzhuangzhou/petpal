import Foundation

struct ChatReplyResponse: Decodable, Sendable {
    let reply: String
    let petID: Int
    let relatedEvents: [RelatedEvent]

    enum CodingKeys: String, CodingKey {
        case reply
        case petID = "pet_id"
        case relatedEvents = "related_events"
    }
}

struct ProactiveChatMessageResponse: Decodable, Sendable {
    let message: ChatMessage
    let notificationTitle: String
    let notificationBody: String
    let matched: Bool

    enum CodingKeys: String, CodingKey {
        case message
        case notificationTitle = "notification_title"
        case notificationBody = "notification_body"
        case matched
    }
}
