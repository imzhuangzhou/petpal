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
        style: String,
        ownerAlias: String
    ) {
        session.petId = response.id
        session.petName = name
        session.petSpecies = species
        session.petPhotoURL = response.photoURL
        session.petAvatarURL = response.avatarURL
        session.languageStyle = style
        session.ownerAlias = response.ownerAlias.isEmpty ? ownerAlias : response.ownerAlias
    }

    func applyUploadedDemoVideo(_ response: DemoVideoUploadResponse) {
        session.cameraId = response.cameraID
        session.cameraName = response.cameraName
        session.demoVideoName = response.demoVideoName
        session.demoVideoURL = response.demoVideoURL
        session.setupComplete = true
    }

    func reset() {
        sessionStore.clear()
        session = AppSession()
    }
}
