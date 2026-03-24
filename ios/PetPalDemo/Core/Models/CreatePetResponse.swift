import Foundation

enum AvatarGenerationJobStatus: String, Decodable, Sendable {
    case queued
    case processing
    case completed
    case failed

    var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            return true
        case .queued, .processing:
            return false
        }
    }
}

struct GeneratedPetAvatarResponse: Decodable, Sendable {
    let jobID: String?
    let status: AvatarGenerationJobStatus
    let photoURL: String
    let avatarURL: String
    let generationError: String?

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
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
    let languageStyle: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case species
        case photoURL = "photo_url"
        case avatarURL = "avatar_url"
        case ownerAlias = "owner_alias"
        case languageStyle = "language_style"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        species = try container.decode(String.self, forKey: .species)
        photoURL = try container.decode(String.self, forKey: .photoURL)
        avatarURL = try container.decode(String.self, forKey: .avatarURL)
        ownerAlias = try container.decodeIfPresent(String.self, forKey: .ownerAlias) ?? ""
        languageStyle = try container.decodeIfPresent(String.self, forKey: .languageStyle) ?? "tsundere"
    }
}
