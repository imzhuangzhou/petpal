import Foundation

final class APIClient {
    struct VoiceSampleUploadResponse: Decodable, Sendable {
        let voiceType: String
        let voiceKey: String
        let voiceLabel: String
        let voiceSampleURL: String

        enum CodingKeys: String, CodingKey {
            case voiceType = "voice_type"
            case voiceKey = "voice_key"
            case voiceLabel = "voice_label"
            case voiceSampleURL = "voice_sample_url"
        }
    }

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
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
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

    func uploadPetVoiceSample(
        petID: Int,
        label: String,
        audioFileURL: URL
    ) async throws -> VoiceSampleUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try MultipartFormDataBuilder.makeBody(
            fields: [MultipartFormDataField(name: "label", value: label)],
            files: [MultipartFormDataFile(fieldName: "audio", fileURL: audioFileURL)],
            boundary: boundary
        )

        return try await upload(
            endpoint: Endpoint(path: "/api/pet/\(petID)/voice/sample", method: .post),
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    func sendChat(petID: Int, message: String) async throws -> ChatReplyResponse {
        try await send(
            endpoint: Endpoint(path: "/api/chat", method: .post),
            body: ChatRequest(petID: petID, message: message)
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
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase

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
        contentType: String
    ) async throws -> Response {
        var request = try makeRequest(for: endpoint)
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
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
