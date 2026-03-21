import Foundation

struct CreateUserRequest: Encodable, Sendable {
    let nickname: String
    let avatarURL: String

    init(nickname: String, avatarURL: String = "") {
        self.nickname = nickname
        self.avatarURL = avatarURL
    }

    enum CodingKeys: String, CodingKey {
        case nickname
        case avatarURL = "avatar_url"
    }
}
