import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

struct Endpoint: Sendable {
    let path: String
    var method: HTTPMethod = .get
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]

    func url(relativeTo baseURL: URL) throws -> URL {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(normalizedPath),
            resolvingAgainstBaseURL: true
        ) else {
            throw APIError.invalidURL(path: path)
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL(path: path)
        }

        return url
    }
}
