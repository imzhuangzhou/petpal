import Foundation

enum AppEnvironment {
    private static let apiBaseURLKey = "API_BASE_URL"

    static var apiBaseURLString: String {
        guard
            let configuredValue = Bundle.main.object(forInfoDictionaryKey: apiBaseURLKey) as? String,
            !configuredValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            preconditionFailure("Missing required Info.plist value: \(apiBaseURLKey)")
        }

        return configuredValue
    }

    static var apiBaseURL: URL {
        guard let url = URL(string: apiBaseURLString), let scheme = url.scheme else {
            preconditionFailure("Invalid API base URL: \(apiBaseURLString)")
        }

        guard scheme == "http" || scheme == "https" else {
            preconditionFailure("Unsupported API base URL scheme: \(scheme)")
        }

        return url
    }
}
