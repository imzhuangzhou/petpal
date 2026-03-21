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
    let voiceType: String
    let voiceKey: String
    let voiceLabel: String
    let voiceSamplePath: String

    init(
        userID: Int,
        name: String,
        breed: String = "",
        species: String = "cat",
        photoURL: String = "",
        avatarURL: String = "",
        languageStyle: String = "tsundere",
        stylePrompt: String = "",
        voiceType: String = "preset",
        voiceKey: String = "cat-soft",
        voiceLabel: String = "奶呼噜",
        voiceSamplePath: String = ""
    ) {
        self.userID = userID
        self.name = name
        self.breed = breed
        self.species = species
        self.photoURL = photoURL
        self.avatarURL = avatarURL
        self.languageStyle = languageStyle
        self.stylePrompt = stylePrompt
        self.voiceType = voiceType
        self.voiceKey = voiceKey
        self.voiceLabel = voiceLabel
        self.voiceSamplePath = voiceSamplePath
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
        case voiceType = "voice_type"
        case voiceKey = "voice_key"
        case voiceLabel = "voice_label"
        case voiceSamplePath = "voice_sample_path"
    }
}
