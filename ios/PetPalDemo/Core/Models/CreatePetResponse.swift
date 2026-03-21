import Foundation

struct GeneratedPetAvatarResponse: Decodable, Sendable {
    let photoURL: String
    let avatarURL: String
    let generationError: String?

    enum CodingKeys: String, CodingKey {
        case photoURL = "photo_url"
        case avatarURL = "avatar_url"
        case generationError = "generation_error"
    }
}

struct CreatePetResponse: Decodable, Sendable {
    let id: Int
    let name: String
    let species: String
    let photoURL: String
    let avatarURL: String
    let voiceType: String
    let voiceKey: String
    let voiceLabel: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case species
        case photoURL = "photo_url"
        case avatarURL = "avatar_url"
        case voiceType = "voice_type"
        case voiceKey = "voice_key"
        case voiceLabel = "voice_label"
    }
}
