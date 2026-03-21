import Foundation

struct AnxietyResponse: Decodable, Sendable {
    let score: Int
    let level: String
    let comment: String
    let waitingCount: Int
    let totalWaitingMinutes: Double
    let petID: Int

    enum CodingKeys: String, CodingKey {
        case score
        case level
        case comment
        case waitingCount = "waiting_count"
        case totalWaitingMinutes = "total_waiting_minutes"
        case petID = "pet_id"
    }
}
