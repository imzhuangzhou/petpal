import Foundation

struct HealthAlertsResponse: Decodable, Sendable {
    let alerts: [HealthAlert]
    let petID: Int

    enum CodingKeys: String, CodingKey {
        case alerts
        case petID = "pet_id"
    }
}
