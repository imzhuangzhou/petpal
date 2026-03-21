import Foundation

struct DiaryResponse: Decodable, Sendable {
    let diary: String
    let petID: Int

    enum CodingKeys: String, CodingKey {
        case diary
        case petID = "pet_id"
    }
}
