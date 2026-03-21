import Foundation

struct CreatePetResponse: Decodable, Sendable {
    let id: Int
    let name: String
    let species: String
    let voiceType: String
    let voiceKey: String
    let voiceLabel: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case species
        case voiceType = "voice_type"
        case voiceKey = "voice_key"
        case voiceLabel = "voice_label"
    }
}
