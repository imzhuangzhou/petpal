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
