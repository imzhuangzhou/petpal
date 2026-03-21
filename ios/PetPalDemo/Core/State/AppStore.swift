import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var session: AppSession {
        didSet {
            sessionStore.save(session)
        }
    }

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
        style: String
    ) {
        session.petId = response.id
        session.petName = name
        session.petSpecies = species
        session.languageStyle = style
        session.voiceType = response.voiceType
        session.voiceKey = response.voiceKey
        session.voiceLabel = response.voiceLabel
        session.voiceSampleURL = ""
    }

    func applyUploadedVoiceSample(_ response: APIClient.VoiceSampleUploadResponse) {
        session.voiceType = response.voiceType
        session.voiceKey = response.voiceKey
        session.voiceLabel = response.voiceLabel
        session.voiceSampleURL = response.voiceSampleURL
    }

    func applyUploadedDemoVideo(_ response: DemoVideoUploadResponse) {
        session.cameraId = response.cameraID
        session.demoVideoName = response.demoVideoName
        session.demoVideoURL = response.demoVideoURL
        session.setupComplete = true
    }

    func reset() {
        sessionStore.clear()
        session = AppSession()
    }
}
