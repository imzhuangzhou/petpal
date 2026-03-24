import Foundation

struct AppSession: Codable {
    var userId: Int?
    var nickname: String
    var ownerAlias: String
    var petId: Int?
    var petName: String
    var petSpecies: String
    var petPhotoURL: String
    var petAvatarURL: String
    var petDefaultAvatarAssetName: String
    var languageStyle: String
    var cameraId: Int?
    var cameraName: String
    var demoVideoName: String
    var demoVideoURL: String
    var analysisJobID: String
    var analysisProcessingStatus: String
    var setupComplete: Bool

    init(
        userId: Int? = nil,
        nickname: String = "",
        ownerAlias: String = "",
        petId: Int? = nil,
        petName: String = "",
        petSpecies: String = "cat",
        petPhotoURL: String = "",
        petAvatarURL: String = "",
        petDefaultAvatarAssetName: String = "",
        languageStyle: String = "tsundere",
        cameraId: Int? = nil,
        cameraName: String = "",
        demoVideoName: String = "",
        demoVideoURL: String = "",
        analysisJobID: String = "",
        analysisProcessingStatus: String = "",
        setupComplete: Bool = false
    ) {
        self.userId = userId
        self.nickname = nickname
        self.ownerAlias = ownerAlias
        self.petId = petId
        self.petName = petName
        self.petSpecies = petSpecies
        self.petPhotoURL = petPhotoURL
        self.petAvatarURL = petAvatarURL
        self.petDefaultAvatarAssetName = petDefaultAvatarAssetName
        self.languageStyle = languageStyle
        self.cameraId = cameraId
        self.cameraName = cameraName
        self.demoVideoName = demoVideoName
        self.demoVideoURL = demoVideoURL
        self.analysisJobID = analysisJobID
        self.analysisProcessingStatus = analysisProcessingStatus
        self.setupComplete = setupComplete
    }

    enum CodingKeys: String, CodingKey {
        case userId
        case nickname
        case ownerAlias
        case petId
        case petName
        case petSpecies
        case petPhotoURL
        case petAvatarURL
        case petDefaultAvatarAssetName
        case languageStyle
        case cameraId
        case cameraName
        case demoVideoName
        case demoVideoURL
        case analysisJobID
        case analysisProcessingStatus
        case setupComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        ownerAlias = try container.decodeIfPresent(String.self, forKey: .ownerAlias) ?? ""
        petId = try container.decodeIfPresent(Int.self, forKey: .petId)
        petName = try container.decodeIfPresent(String.self, forKey: .petName) ?? ""
        petSpecies = try container.decodeIfPresent(String.self, forKey: .petSpecies) ?? "cat"
        petPhotoURL = try container.decodeIfPresent(String.self, forKey: .petPhotoURL) ?? ""
        petAvatarURL = try container.decodeIfPresent(String.self, forKey: .petAvatarURL) ?? ""
        petDefaultAvatarAssetName = try container.decodeIfPresent(String.self, forKey: .petDefaultAvatarAssetName) ?? ""
        languageStyle = try container.decodeIfPresent(String.self, forKey: .languageStyle) ?? "tsundere"
        cameraId = try container.decodeIfPresent(Int.self, forKey: .cameraId)
        cameraName = try container.decodeIfPresent(String.self, forKey: .cameraName) ?? ""
        demoVideoName = try container.decodeIfPresent(String.self, forKey: .demoVideoName) ?? ""
        demoVideoURL = try container.decodeIfPresent(String.self, forKey: .demoVideoURL) ?? ""
        analysisJobID = try container.decodeIfPresent(String.self, forKey: .analysisJobID) ?? ""
        analysisProcessingStatus = try container.decodeIfPresent(String.self, forKey: .analysisProcessingStatus) ?? ""
        setupComplete = try container.decodeIfPresent(Bool.self, forKey: .setupComplete) ?? false
    }
}
