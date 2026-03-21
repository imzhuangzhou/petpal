import Foundation

struct DailyReportResponse: Decodable, Sendable {
    let report: String
    let petID: Int

    enum CodingKeys: String, CodingKey {
        case report
        case petID = "pet_id"
    }
}
