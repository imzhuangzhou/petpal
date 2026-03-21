import Foundation

final class SessionStore {
    private let defaults: UserDefaults
    private let sessionKey = "petpal-ios-demo-session"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSession? {
        guard let data = defaults.data(forKey: sessionKey) else {
            return nil
        }

        return try? JSONDecoder().decode(AppSession.self, from: data)
    }

    func save(_ session: AppSession) {
        guard let data = try? JSONEncoder().encode(session) else {
            return
        }

        defaults.set(data, forKey: sessionKey)
    }

    func clear() {
        defaults.removeObject(forKey: sessionKey)
    }
}
