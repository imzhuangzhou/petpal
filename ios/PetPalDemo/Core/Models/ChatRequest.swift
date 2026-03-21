import Foundation

struct ChatRequest: Encodable, Sendable {
    let petID: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case petID = "pet_id"
        case message
    }
}
