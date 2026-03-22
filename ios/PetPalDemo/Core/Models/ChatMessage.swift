import Foundation

struct ChatMessage: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let role: Role
    var content: String
    var relatedEvents: [RelatedEvent]
    var displayStyle: DisplayStyle
    var voiceAudioURL: URL?
    var voiceDurationSeconds: Int?
    var voiceTranscript: String?
    var messageType: MessageType
    var mediaKind: MediaKind
    var mediaURL: String
    var triggerSource: TriggerSource
    var createdAt: String?

    init(
        id: String = UUID().uuidString,
        role: Role,
        content: String,
        relatedEvents: [RelatedEvent] = [],
        displayStyle: DisplayStyle = .text,
        voiceAudioURL: URL? = nil,
        voiceDurationSeconds: Int? = nil,
        voiceTranscript: String? = nil,
        messageType: MessageType = .text,
        mediaKind: MediaKind = .none,
        mediaURL: String = "",
        triggerSource: TriggerSource = .chat,
        createdAt: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.relatedEvents = relatedEvents
        self.displayStyle = displayStyle
        self.voiceAudioURL = voiceAudioURL
        self.voiceDurationSeconds = voiceDurationSeconds
        self.voiceTranscript = voiceTranscript
        self.messageType = messageType
        self.mediaKind = mediaKind
        self.mediaURL = mediaURL
        self.triggerSource = triggerSource
        self.createdAt = createdAt
    }

    enum Role: String, Hashable, Sendable, Decodable {
        case user
        case assistant
    }

    enum DisplayStyle: Hashable, Sendable {
        case text
        case voice
    }

    enum MessageType: String, Hashable, Sendable, Decodable {
        case text
        case video
    }

    enum MediaKind: String, Hashable, Sendable, Decodable {
        case none = ""
        case video
    }

    enum TriggerSource: String, Hashable, Sendable, Decodable {
        case chat
        case proactiveVocalization = "proactive_vocalization"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case relatedEvents = "related_events"
        case messageType = "message_type"
        case mediaKind = "media_kind"
        case mediaURL = "media_url"
        case triggerSource = "trigger_source"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = UUID().uuidString
        }

        role = try container.decode(Role.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        relatedEvents = try container.decodeIfPresent([RelatedEvent].self, forKey: .relatedEvents) ?? []
        displayStyle = .text
        voiceAudioURL = nil
        voiceDurationSeconds = nil
        voiceTranscript = nil
        messageType = try container.decodeIfPresent(MessageType.self, forKey: .messageType) ?? .text
        mediaKind = try container.decodeIfPresent(MediaKind.self, forKey: .mediaKind) ?? .none
        mediaURL = try container.decodeIfPresent(String.self, forKey: .mediaURL) ?? ""
        triggerSource = try container.decodeIfPresent(TriggerSource.self, forKey: .triggerSource) ?? .chat
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}
