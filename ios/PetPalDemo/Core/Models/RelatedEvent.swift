import Foundation

struct RelatedEvent: Decodable, Sendable, Identifiable, Hashable {
    var id: Int { eventId }

    let eventId: Int
    let eventType: String
    let description: String
    let timestamp: String
    let videoClipUrl: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventType = "event_type"
        case description
        case timestamp
        case videoClipUrl = "video_clip_url"
    }
}
