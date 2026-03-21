import Foundation

struct HealthAlert: Decodable, Sendable, Hashable {
    let level: String
    let title: String
    let message: String
}
