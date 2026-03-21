import Foundation

struct CreateUserResponse: Decodable, Sendable {
    let id: Int
    let nickname: String
}
