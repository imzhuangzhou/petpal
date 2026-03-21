import Foundation

struct AppSession: Codable {
    var userId: Int?
    var nickname: String
    var petId: Int?
    var petName: String
    var petSpecies: String
    var languageStyle: String
    var voiceType: String
    var voiceKey: String
    var voiceLabel: String
    var voiceSampleURL: String
    var cameraId: Int?
    var demoVideoName: String
    var demoVideoURL: String
    var setupComplete: Bool

    init(
        userId: Int? = nil,
        nickname: String = "",
        petId: Int? = nil,
        petName: String = "",
        petSpecies: String = "cat",
        languageStyle: String = "tsundere",
        voiceType: String = "preset",
        voiceKey: String = "cat-soft",
        voiceLabel: String = "奶呼噜",
        voiceSampleURL: String = "",
        cameraId: Int? = nil,
        demoVideoName: String = "",
        demoVideoURL: String = "",
        setupComplete: Bool = false
    ) {
        self.userId = userId
        self.nickname = nickname
        self.petId = petId
        self.petName = petName
        self.petSpecies = petSpecies
        self.languageStyle = languageStyle
        self.voiceType = voiceType
        self.voiceKey = voiceKey
        self.voiceLabel = voiceLabel
        self.voiceSampleURL = voiceSampleURL
        self.cameraId = cameraId
        self.demoVideoName = demoVideoName
        self.demoVideoURL = demoVideoURL
        self.setupComplete = setupComplete
    }
}
