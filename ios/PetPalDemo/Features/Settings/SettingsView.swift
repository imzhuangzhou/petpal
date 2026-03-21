import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedVideo: PickedVideo?
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("当前会话") {
                LabeledContent("用户 ID", value: appStore.session.userId.map(String.init) ?? "-")
                LabeledContent("宠物 ID", value: appStore.session.petId.map(String.init) ?? "-")
                LabeledContent("摄像头 ID", value: appStore.session.cameraId.map(String.init) ?? "-")
                LabeledContent("视频名", value: appStore.session.demoVideoName)
            }

            Section("替换演示视频") {
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label(selectedVideo == nil ? "选择新视频" : "重新选择视频", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .onChange(of: selectedItem) {
                    Task {
                        await loadSelectedVideo()
                    }
                }

                if let selectedVideo {
                    LabeledContent("待上传文件", value: selectedVideo.url.lastPathComponent)
                }

                Button {
                    Task {
                        await replaceVideo()
                    }
                } label: {
                    if isUploading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("上传替换视频")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(
                    isUploading ||
                    appStore.session.userId == nil ||
                    appStore.session.petId == nil ||
                    selectedVideo == nil
                )
                .buttonStyle(.bordered)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("环境") {
                LabeledContent("API Base URL", value: appStore.apiClient.baseURL.absoluteString)
                LabeledContent(
                    "当前视频 URL",
                    value: appStore.apiClient.resolvedURL(for: appStore.session.demoVideoURL)?.absoluteString ?? "-"
                )
            }

            Section("操作") {
                Button("重置本地演示状态", role: .destructive) {
                    appStore.reset()
                    dismiss()
                }
            }
        }
        .navigationTitle("设置")
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

    private func replaceVideo() async {
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
                    cameraName: "家庭摄像头",
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
