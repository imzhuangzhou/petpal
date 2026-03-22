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
    let ownerAlias: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case species
        case photoURL = "photo_url"
        case avatarURL = "avatar_url"
        case ownerAlias = "owner_alias"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        species = try container.decode(String.self, forKey: .species)
        photoURL = try container.decode(String.self, forKey: .photoURL)
        avatarURL = try container.decode(String.self, forKey: .avatarURL)
        ownerAlias = try container.decodeIfPresent(String.self, forKey: .ownerAlias) ?? ""
    }
}
