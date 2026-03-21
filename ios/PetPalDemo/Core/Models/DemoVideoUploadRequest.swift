import Foundation

struct DemoVideoUploadRequest: Sendable {
    let userID: Int
    let petID: Int
    let cameraName: String
    let cameraID: Int?
    let videoFileURL: URL

    init(
        userID: Int,
        petID: Int,
        cameraName: String = "家庭摄像头",
        cameraID: Int? = nil,
        videoFileURL: URL
    ) {
        self.userID = userID
        self.petID = petID
        self.cameraName = cameraName
        self.cameraID = cameraID
        self.videoFileURL = videoFileURL
    }
}
