import Foundation

enum OnboardingRoute: Equatable {
    case derivedFromSession
    case petSetup(step: Int)
    case cameraSetup
}

enum AvatarGenerationState: Equatable {
    case idle
    case generating
    case generated
    case failed
}

enum AvatarInputMode: Equatable {
    case photoGenerated
    case defaultArt
}

struct PetSetupDraft: Equatable {
    var petName: String
    var ownerAlias: String
    var species: String
    var style: String
    var avatarInputMode: AvatarInputMode
    var selectedCatDefaultAvatarID: String
    var selectedDogDefaultAvatarID: String
    var referencePhotoRemotePath: String
    var generatedAvatarRemotePath: String
    var avatarGenerationState: AvatarGenerationState
    var avatarMessage: String?
    var defaultAvatarAssetName: String
}

@MainActor
final class AppStore: ObservableObject {
    @Published var session: AppSession {
        didSet {
            sessionStore.save(session)
        }
    }
    @Published var onboardingRoute: OnboardingRoute = .derivedFromSession
    @Published var petSetupDraft: PetSetupDraft?

    let apiClient: APIClient
    private let sessionStore: SessionStore

    init(
        sessionStore: SessionStore = SessionStore(),
        apiClient: APIClient = APIClient()
    ) {
        self.sessionStore = sessionStore
        self.apiClient = apiClient
        self.session = sessionStore.load() ?? AppSession()
    }

    func applyCreatedUser(_ response: CreateUserResponse) {
        session.userId = response.id
        session.nickname = response.nickname
    }

    func applyCreatedPet(
        response: CreatePetResponse,
        name: String,
        species: String,
        style _: String,
        ownerAlias: String,
        defaultAvatarAssetName: String
    ) {
        session.petId = response.id
        session.petName = name
        session.petSpecies = species
        session.petPhotoURL = response.photoURL
        session.petAvatarURL = response.avatarURL
        session.petDefaultAvatarAssetName = defaultAvatarAssetName
        session.languageStyle = response.languageStyle
        session.ownerAlias = response.ownerAlias.isEmpty ? ownerAlias : response.ownerAlias
    }

    func applyUpdatedPet(
        response: CreatePetResponse,
        fallbackName: String,
        fallbackOwnerAlias: String,
        defaultAvatarAssetName: String
    ) {
        session.petId = response.id
        session.petName = response.name.ifEmpty(fallbackName)
        session.petSpecies = response.species
        session.petPhotoURL = response.photoURL
        session.petAvatarURL = response.avatarURL
        session.petDefaultAvatarAssetName = defaultAvatarAssetName
        session.languageStyle = response.languageStyle
        session.ownerAlias = response.ownerAlias.ifEmpty(fallbackOwnerAlias)
    }

    func applyPetSetupDraft(_ draft: PetSetupDraft) {
        petSetupDraft = draft
    }

    func applyPetSetupDraftToSession(_ draft: PetSetupDraft) {
        session.petName = draft.petName
        session.ownerAlias = draft.ownerAlias
        session.petSpecies = draft.species
        session.languageStyle = draft.style
        if draft.avatarInputMode == .defaultArt {
            session.petPhotoURL = ""
            session.petAvatarURL = ""
            session.petDefaultAvatarAssetName = draft.defaultAvatarAssetName
        } else {
            session.petPhotoURL = draft.referencePhotoRemotePath
            session.petAvatarURL = draft.generatedAvatarRemotePath
            session.petDefaultAvatarAssetName = ""
        }
    }

    func applyUploadedDemoVideo(_ response: DemoVideoUploadResponse) {
        session.cameraId = response.cameraID
        session.cameraName = response.cameraName
        session.demoVideoName = response.demoVideoName
        session.demoVideoURL = response.demoVideoURL
        session.setupComplete = true
        petSetupDraft = nil
        onboardingRoute = .derivedFromSession
    }

    func reset() {
        sessionStore.clear()
        session = AppSession()
        petSetupDraft = nil
        onboardingRoute = .derivedFromSession
    }
}
