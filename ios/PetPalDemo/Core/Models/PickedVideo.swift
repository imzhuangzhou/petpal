import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct PickedVideo: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let fileManager = FileManager.default
            let fileExtension = received.file.pathExtension
            let destination = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            try fileManager.copyItem(at: received.file, to: destination)
            return PickedVideo(url: destination)
        }
    }
}
