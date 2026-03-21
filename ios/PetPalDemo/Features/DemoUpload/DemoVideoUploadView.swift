import SwiftUI
import PhotosUI

struct DemoVideoUploadView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var cameraName = "家庭摄像头"
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedVideo: PickedVideo?
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("演示视频") {
                TextField("展示名称", text: $cameraName)

                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label(selectedVideo == nil ? "选择演示视频" : "重新选择视频", systemImage: "video.badge.plus")
                }
                .accessibilityHint("从系统照片中选择一个演示视频")
                .onChange(of: selectedItem) {
                    Task {
                        await loadSelectedVideo()
                    }
                }

                if let selectedVideo {
                    LabeledContent("已选择文件", value: selectedVideo.url.lastPathComponent)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("上传") {
                Button {
                    Task {
                        await uploadVideo()
                    }
                } label: {
                    if isUploading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("上传并进入聊天")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(
                    isUploading ||
                    appStore.session.userId == nil ||
                    appStore.session.petId == nil ||
                    selectedVideo == nil
                )
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Upload Demo Video")
    }

    private func loadSelectedVideo() async {
        errorMessage = nil

        guard let selectedItem else {
            selectedVideo = nil
            return
        }

        do {
            selectedVideo = try await selectedItem.loadTransferable(type: PickedVideo.self)
        } catch {
            selectedVideo = nil
            errorMessage = "无法读取所选视频，请重新选择。"
        }
    }

    private func uploadVideo() async {
        guard
            let userID = appStore.session.userId,
            let petID = appStore.session.petId,
            let selectedVideo
        else {
            return
        }

        isUploading = true
        errorMessage = nil

        do {
            let response = try await appStore.apiClient.uploadDemoVideo(
                DemoVideoUploadRequest(
                    userID: userID,
                    petID: petID,
                    cameraName: cameraName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "家庭摄像头" : cameraName,
                    cameraID: appStore.session.cameraId,
                    videoFileURL: selectedVideo.url
                )
            )

            appStore.applyUploadedDemoVideo(response)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isUploading = false
    }
}
