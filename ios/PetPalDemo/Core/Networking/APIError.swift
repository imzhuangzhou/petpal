import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case invalidURL(path: String)
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case noConnection
    case timedOut
    case cancelled
    case encodingFailed(String)
    case decodingFailed(String)
    case fileReadFailed(path: String)
    case requestFailed(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "无法构造接口地址：\(path)"
        case .invalidResponse:
            return "服务端返回了无效响应。"
        case .httpError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "请求失败（\(statusCode)）：\(message)"
            }
            return "请求失败，HTTP 状态码：\(statusCode)"
        case .noConnection:
            return "当前网络不可用，请检查连接。"
        case .timedOut:
            return "请求超时，请稍后重试。"
        case .cancelled:
            return "请求已取消。"
        case .encodingFailed(let message):
            return "请求编码失败：\(message)"
        case .decodingFailed(let message):
            return "响应解析失败：\(message)"
        case .fileReadFailed(let path):
            return "无法读取上传文件：\(path)"
        case .requestFailed(let message):
            return "网络请求失败：\(message)"
        case .unexpected(let message):
            return "发生了未预期错误：\(message)"
        }
    }

    static func from(_ urlError: URLError) -> APIError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        default:
            return .requestFailed(urlError.localizedDescription)
        }
    }

    static func serverMessage(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(ServerErrorPayload.self, from: data) {
            let trimmed = payload.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let rawString = String(data: data, encoding: .utf8) {
            let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }
}

private struct ServerErrorPayload: Decodable {
    let detail: String
}
