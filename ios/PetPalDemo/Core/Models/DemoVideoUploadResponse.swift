import Foundation

struct DemoVideoUploadResponse: Decodable, Sendable {
    let cameraID: Int
    let cameraName: String
    let demoVideoName: String
    let demoVideoURL: String
    let jobID: String?
    let processingStatus: String?
    let contextSummary: String
    let eventsCount: Int

    enum CodingKeys: String, CodingKey {
        case cameraID = "camera_id"
        case cameraName = "camera_name"
        case demoVideoName = "demo_video_name"
        case demoVideoURL = "demo_video_url"
        case jobID = "job_id"
        case processingStatus = "processing_status"
        case contextSummary = "context_summary"
        case eventsCount = "events_count"
    }
}
