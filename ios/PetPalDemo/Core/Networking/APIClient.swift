import Foundation

final class APIClient {
    private static let avatarGenerationRequestTimeout: TimeInterval = 60

    let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL = AppEnvironment.apiBaseURL,
        session: URLSession = APIClient.makeSession(),
        encoder: JSONEncoder = APIClient.makeEncoder(),
        decoder: JSONDecoder = APIClient.makeDecoder()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = encoder
        self.decoder = decoder
    }

    func endpoint(_ path: String) -> URL {
        let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(sanitizedPath)
    }

    func resolvedURL(for path: String) -> URL? {
        if let url = URL(string: path), url.scheme != nil {
            return url
        }

        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return endpoint(path)
    }

    func createUser(nickname: String, avatarURL: String = "") async throws -> CreateUserResponse {
        try await send(
            endpoint: Endpoint(path: "/api/user", method: .post),
            body: CreateUserRequest(nickname: nickname, avatarURL: avatarURL),
            timeoutInterval: 5
        )
    }

    func createPet(_ requestBody: CreatePetRequest) async throws -> CreatePetResponse {
        try await send(
            endpoint: Endpoint(path: "/api/pet", method: .post),
            body: requestBody
        )
    }

    func updatePet(petID: Int, requestBody: UpdatePetRequest) async throws -> CreatePetResponse {
        try await send(
            endpoint: Endpoint(path: "/api/pet/\(petID)", method: .patch),
            body: requestBody
        )
    }

    func generatePetAvatar(
        species: String,
        imageFileURL: URL
    ) async throws -> GeneratedPetAvatarResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try MultipartFormDataBuilder.makeBody(
            fields: [MultipartFormDataField(name: "species", value: species)],
            files: [MultipartFormDataFile(fieldName: "image", fileURL: imageFileURL)],
            boundary: boundary
        )

        return try await upload(
            endpoint: Endpoint(path: "/api/pet/avatar/generate", method: .post),
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            timeoutInterval: Self.avatarGenerationRequestTimeout
        )
    }

    func fetchPetAvatarGenerationJob(jobID: String) async throws -> GeneratedPetAvatarResponse {
        try await fetch(endpoint: Endpoint(path: "/api/pet/avatar/generate/\(jobID)"))
    }

    func uploadDemoVideo(_ requestBody: DemoVideoUploadRequest) async throws -> DemoVideoUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var fields = [
            MultipartFormDataField(name: "user_id", value: String(requestBody.userID)),
            MultipartFormDataField(name: "pet_id", value: String(requestBody.petID)),
            MultipartFormDataField(name: "camera_name", value: requestBody.cameraName),
        ]

        if let cameraID = requestBody.cameraID {
            fields.append(MultipartFormDataField(name: "camera_id", value: String(cameraID)))
        }

        let body = try MultipartFormDataBuilder.makeBody(
            fields: fields,
            files: [MultipartFormDataFile(fieldName: "video", fileURL: requestBody.videoFileURL)],
            boundary: boundary
        )

        return try await upload(
            endpoint: Endpoint(path: "/api/demo-video", method: .post),
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    func fetchVideoAnalysisDebug(cameraID: Int) async throws -> VideoAnalysisDebugResponse {
        try await fetch(endpoint: Endpoint(path: "/api/debug/video-analysis/\(cameraID)"))
    }

    func fetchEventClip(eventID: Int) async throws -> EventClipResponse {
        try await fetch(endpoint: Endpoint(path: "/api/events/\(eventID)/clip"))
    }

    func sendChat(petID: Int, message: String) async throws -> ChatReplyResponse {
        try await send(
            endpoint: Endpoint(path: "/api/chat", method: .post),
            body: ChatRequest(petID: petID, message: message)
        )
    }

    func fetchChatHistory(petID: Int, limit: Int = 50) async throws -> [ChatMessage] {
        try await fetch(
            endpoint: Endpoint(
                path: "/api/chat/history/\(petID)",
                queryItems: [URLQueryItem(name: "limit", value: String(limit))]
            )
        )
    }

    func triggerProactiveVocalization(
        petID: Int,
        cameraID: Int
    ) async throws -> ProactiveChatMessageResponse {
        try await send(
            endpoint: Endpoint(path: "/api/chat/proactive/vocalization", method: .post),
            body: ProactiveVocalizationRequest(petID: petID, cameraID: cameraID)
        )
    }

    /// SSE streaming chat: calls `onToken` for each received token,
    /// then `onDone` with related events when the stream finishes.
    func sendChatStream(
        petID: Int,
        message: String,
        onToken: @Sendable @escaping (String) async -> Void,
        onDone: @Sendable @escaping ([RelatedEvent]) async -> Void
    ) async throws {
        let body = ChatRequest(petID: petID, message: message)
        let requestBody: Data
        do {
            requestBody = try encoder.encode(body)
        } catch {
            throw APIError.encodingFailed(error.localizedDescription)
        }

        let ep = Endpoint(path: "/api/chat/stream", method: .post)
        var request = try makeRequest(for: ep)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60
        request.httpBody = requestBody

        let (stream, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let jsonDecoder = JSONDecoder()

        for try await line in stream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            guard let data = payload.data(using: .utf8) else { continue }

            // Try to decode as done message
            struct DoneMessage: Decodable {
                let done: Bool?
                let relatedEvents: [RelatedEvent]?
                enum CodingKeys: String, CodingKey {
                    case done
                    case relatedEvents = "related_events"
                }
            }

            if let doneMsg = try? jsonDecoder.decode(DoneMessage.self, from: data),
               doneMsg.done == true {
                await onDone(doneMsg.relatedEvents ?? [])
                break
            }

            // Try to decode as token message
            struct TokenMessage: Decodable {
                let token: String
            }

            if let tokenMsg = try? jsonDecoder.decode(TokenMessage.self, from: data) {
                await onToken(tokenMsg.token)
            }
        }
    }

    func fetchDailyReport(petID: Int) async throws -> DailyReportResponse {
        try await fetch(endpoint: Endpoint(path: "/api/report/daily/\(petID)"))
    }

    func fetchHealthAlerts(petID: Int) async throws -> HealthAlertsResponse {
        try await fetch(endpoint: Endpoint(path: "/api/health/alerts/\(petID)"))
    }

    func fetchAnxiety(petID: Int) async throws -> AnxietyResponse {
        try await fetch(endpoint: Endpoint(path: "/api/anxiety/\(petID)"))
    }

    func fetchDiary(petID: Int) async throws -> DiaryResponse {
        try await fetch(endpoint: Endpoint(path: "/api/diary/\(petID)"))
    }

    private func fetch<Response: Decodable & Sendable>(
        endpoint: Endpoint
    ) async throws -> Response {
        let request = try makeRequest(for: endpoint)
        return try await execute(request)
    }

    private func send<Response: Decodable & Sendable, Body: Encodable & Sendable>(
        endpoint: Endpoint,
        body: Body,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> Response {
        let requestBody: Data
        do {
            requestBody = try encoder.encode(body)
        } catch {
            throw APIError.encodingFailed(error.localizedDescription)
        }

        var request = try makeRequest(for: endpoint, timeoutInterval: timeoutInterval)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        return try await execute(request, uploadBody: requestBody)
    }

    private func upload<Response: Decodable & Sendable>(
        endpoint: Endpoint,
        body: Data,
        contentType: String,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> Response {
        var request = try makeRequest(for: endpoint, timeoutInterval: timeoutInterval)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return try await execute(request, uploadBody: body)
    }

    private func makeRequest(
        for endpoint: Endpoint,
        timeoutInterval: TimeInterval? = nil
    ) throws -> URLRequest {
        let url = try endpoint.url(relativeTo: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = timeoutInterval ?? 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        for (header, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        return request
    }

    private func execute<Response: Decodable & Sendable>(
        _ request: URLRequest,
        uploadBody: Data? = nil
    ) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            if let uploadBody {
                (data, response) = try await session.upload(for: request, from: uploadBody)
            } else {
                (data, response) = try await session.data(for: request)
            }
        } catch let urlError as URLError {
            throw APIError.from(urlError)
        } catch {
            throw APIError.unexpected(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpError(
                statusCode: httpResponse.statusCode,
                message: APIError.serverMessage(from: data)
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Accept-Language": Locale.preferredLanguages.first ?? "zh-Hans",
        ]
        return URLSession(configuration: configuration)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}

struct VideoAnalysisDebugResponse: Decodable, Sendable {
    let cameraID: Int
    let petID: Int?
    let jobID: String?
    let demoVideoName: String
    let demoVideoURL: String
    let contextSummary: String
    let processingStatus: String
    let stepStates: [VideoAnalysisDebugStep]
    let frames: [VideoAnalysisDebugFrame]
    let candidateClips: [VideoAnalysisCandidateClip]
    let events: [VideoAnalysisDebugEvent]
    let lastUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case cameraID = "camera_id"
        case petID = "pet_id"
        case jobID = "job_id"
        case demoVideoName = "demo_video_name"
        case demoVideoURL = "demo_video_url"
        case contextSummary = "context_summary"
        case processingStatus = "processing_status"
        case stepStates = "step_states"
        case frames
        case candidateClips = "candidate_clips"
        case events
        case lastUpdatedAt = "last_updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cameraID = try container.decode(Int.self, forKey: .cameraID)
        petID = try container.decodeIfPresent(Int.self, forKey: .petID)
        jobID = try container.decodeIfPresent(String.self, forKey: .jobID)
        demoVideoName = try container.decodeIfPresent(String.self, forKey: .demoVideoName) ?? ""
        demoVideoURL = try container.decodeIfPresent(String.self, forKey: .demoVideoURL) ?? ""
        contextSummary = try container.decodeIfPresent(String.self, forKey: .contextSummary) ?? ""
        processingStatus = try container.decodeIfPresent(String.self, forKey: .processingStatus) ?? "not_available"
        stepStates = try container.decodeIfPresent([VideoAnalysisDebugStep].self, forKey: .stepStates) ?? []
        frames = try container.decodeIfPresent([VideoAnalysisDebugFrame].self, forKey: .frames) ?? []
        candidateClips = try container.decodeIfPresent([VideoAnalysisCandidateClip].self, forKey: .candidateClips) ?? []
        events = try container.decodeIfPresent([VideoAnalysisDebugEvent].self, forKey: .events) ?? []
        lastUpdatedAt = try container.decodeIfPresent(String.self, forKey: .lastUpdatedAt)
    }
}

struct VideoAnalysisDebugStep: Decodable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let state: String
}

struct VideoAnalysisDebugFrame: Decodable, Sendable, Hashable, Identifiable {
    var id: String { "\(sequence)-\(frameURL)" }

    let sequence: Int
    let frameURL: String
    let videoSeconds: Double
    let videoTimeText: String
    let eventType: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case sequence
        case frameURL = "frame_url"
        case videoSeconds = "video_seconds"
        case videoTimeText = "video_time_text"
        case eventType = "event_type"
        case description
    }
}

struct VideoAnalysisDebugEvent: Decodable, Sendable, Hashable, Identifiable {
    let id: Int
    let eventType: String
    let description: String
    let timestamp: String
    let durationSeconds: Double
    let videoStartSeconds: Double?
    let videoEndSeconds: Double?
    let frameURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case description
        case timestamp
        case durationSeconds = "duration_seconds"
        case videoStartSeconds = "video_start_seconds"
        case videoEndSeconds = "video_end_seconds"
        case frameURL = "frame_url"
    }
}

struct VideoAnalysisCandidateClip: Decodable, Sendable, Hashable, Identifiable {
    let id: Int
    let sequence: Int
    let ruleID: String
    let primaryRule: String
    let secondaryRules: [String]
    let clipURL: String
    let thumbnailURL: String
    let startSeconds: Double
    let endSeconds: Double
    let analysisStatus: String
    let summary: String
    let eventType: String

    enum CodingKeys: String, CodingKey {
        case id
        case sequence
        case ruleID = "rule_id"
        case primaryRule = "primary_rule"
        case secondaryRules = "secondary_rules"
        case clipURL = "clip_url"
        case thumbnailURL = "thumbnail_url"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case analysisStatus = "analysis_status"
        case summary
        case eventType = "event_type"
    }
}

struct EventClipResponse: Decodable, Sendable {
    let eventID: Int
    let videoClipURL: String

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case videoClipURL = "video_clip_url"
    }
}
