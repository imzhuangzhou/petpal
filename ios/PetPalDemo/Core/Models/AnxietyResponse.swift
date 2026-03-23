import Foundation

struct AnxietyResponse: Decodable, Sendable {
    let score: Int
    let level: String
    let comment: String
    let waitingCount: Int
    let totalWaitingMinutes: Double
    let longestWaitingMinutes: Double
    let waitingSharePercent: Int
    let petID: Int

    enum CodingKeys: String, CodingKey {
        case score
        case level
        case comment
        case waitingCount = "waiting_count"
        case totalWaitingMinutes = "total_waiting_minutes"
        case longestWaitingMinutes = "longest_waiting_minutes"
        case waitingSharePercent = "waiting_share_percent"
        case petID = "pet_id"
    }
}
