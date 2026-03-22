import Foundation

struct CreatePetRequest: Encodable, Sendable {
    let userID: Int
    let name: String
    let breed: String
    let species: String
    let photoURL: String
    let avatarURL: String
    let languageStyle: String
    let stylePrompt: String
    let ownerAlias: String

    init(
        userID: Int,
        name: String,
        breed: String = "",
        species: String = "cat",
        photoURL: String = "",
        avatarURL: String = "",
        languageStyle: String = "tsundere",
        stylePrompt: String = "",
        ownerAlias: String = ""
    ) {
        self.userID = userID
        self.name = name
        self.breed = breed
        self.species = species
        self.photoURL = photoURL
        self.avatarURL = avatarURL
        self.languageStyle = languageStyle
        self.stylePrompt = stylePrompt
        self.ownerAlias = ownerAlias
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name
        case breed
        case species
        case photoURL = "photo_url"
        case avatarURL = "avatar_url"
        case languageStyle = "language_style"
        case stylePrompt = "style_prompt"
        case ownerAlias = "owner_alias"
    }
}
