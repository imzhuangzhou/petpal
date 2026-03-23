import Foundation

struct DailyReportResponse: Decodable, Sendable {
    let report: String
    let card: DailyReportCard?
    let petID: Int

    enum CodingKeys: String, CodingKey {
        case report
        case card
        case petID = "pet_id"
    }
}

struct DailyReportCard: Decodable, Sendable {
    let headline: String
    let mood: String
    let summary: String
    let activityTags: [String]
    let stats: DailyReportStats
    let closingLine: String

    enum CodingKeys: String, CodingKey {
        case headline
        case mood
        case summary
        case activityTags = "activity_tags"
        case stats
        case closingLine = "closing_line"
    }
}

struct DailyReportStats: Decodable, Sendable {
    let eating: Int
    let drinking: Int
    let playing: Int
    let waiting: Int
}
