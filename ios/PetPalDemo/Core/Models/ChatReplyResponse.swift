import Foundation

struct ChatReplyResponse: Decodable, Sendable {
    let reply: String
    let petID: Int

    enum CodingKeys: String, CodingKey {
        case reply
        case petID = "pet_id"
    }
}
