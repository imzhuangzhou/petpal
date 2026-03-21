import Foundation
import UniformTypeIdentifiers

struct MultipartFormDataField: Sendable {
    let name: String
    let value: String
}

struct MultipartFormDataFile: Sendable {
    let fieldName: String
    let fileURL: URL
    let fileName: String
    let mimeType: String

    init(fieldName: String, fileURL: URL, fileName: String? = nil, mimeType: String? = nil) {
        self.fieldName = fieldName
        self.fileURL = fileURL
        self.fileName = fileName ?? fileURL.lastPathComponent
        self.mimeType = mimeType ?? MultipartFormDataFile.detectMimeType(for: fileURL)
    }

    private static func detectMimeType(for fileURL: URL) -> String {
        let fileExtension = fileURL.pathExtension
        guard
            !fileExtension.isEmpty,
            let type = UTType(filenameExtension: fileExtension),
            let mimeType = type.preferredMIMEType
        else {
            return "application/octet-stream"
        }

        return mimeType
    }
}

enum MultipartFormDataBuilder {
    static func makeBody(
        fields: [MultipartFormDataField],
        files: [MultipartFormDataFile],
        boundary: String
    ) throws -> Data {
        var body = Data()

        for field in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            body.append("\(field.value)\r\n")
        }

        for file in files {
            let fileData: Data
            do {
                fileData = try Data(contentsOf: file.fileURL)
            } catch {
                throw APIError.fileReadFailed(path: file.fileURL.path)
            }

            body.append("--\(boundary)\r\n")
            body.append(
                "Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n"
            )
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(fileData)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        self.append(string.data(using: .utf8) ?? Data())
    }
}
