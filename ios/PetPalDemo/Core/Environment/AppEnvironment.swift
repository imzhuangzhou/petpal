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
        let configuredValue = apiBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard var components = URLComponents(string: configuredValue), let scheme = components.scheme else {
            preconditionFailure("Invalid API base URL: \(apiBaseURLString)")
        }

        guard scheme == "http" || scheme == "https" else {
            preconditionFailure("Unsupported API base URL scheme: \(scheme)")
        }

        if shouldUseIPv4Loopback(for: components.host) {
            components.host = "127.0.0.1"
        }

        guard let url = components.url else {
            preconditionFailure("Invalid API base URL after normalization: \(configuredValue)")
        }

        return url
    }

    private static func shouldUseIPv4Loopback(for host: String?) -> Bool {
        guard isRunningOnSimulator, let normalizedHost = host?.lowercased() else {
            return false
        }

        return normalizedHost == "localhost" || normalizedHost == "::1"
    }

    private static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
