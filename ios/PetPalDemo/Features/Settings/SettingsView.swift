import AVKit
import PhotosUI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedVideo: PickedVideo?
    @State private var isUploading = false
    @State private var isShowingResetConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        PetPalShell {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        PetPalNavigationHeader(
                            title: "设置",
                            onBack: { dismiss() }
                        )

                        PetPalPanelCard {
                            PetPalSectionHeader(
                                eyebrow: "宠物信息",
                                title: appStore.session.petName.ifEmpty("PetPal"),
                                chipText: nil
                            )

                            PetPalSurfaceCard {
                                PetPalInfoRow(
                                    title: "主人",
                                    value: appStore.session.ownerAlias.ifEmpty(appStore.session.nickname.ifEmpty("你"))
                                )
                                PetPalInfoRow(
                                    title: "种类",
                                    value: appStore.session.petSpecies == "dog" ? "狗狗" : "猫咪"
                                )
                            }
                        }

                        PetPalPanelCard {
                            PetPalSectionHeader(
                                eyebrow: "摄像头",
                                title: "视频上下文",
                                chipText: nil
                            )

                            PetPalSurfaceCard {
                                PetPalInfoRow(
                                    title: "当前摄像头",
                                    value: appStore.session.cameraName.ifEmpty("未绑定")
                                )

                                PetPalInfoRow(
                                    title: "联调视频",
                                    value: appStore.session.demoVideoName.ifEmpty("未上传")
                                )

                                if let selectedVideo {
                                    Text("待上传视频：\(selectedVideo.url.lastPathComponent)")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(PetPalTheme.ink)
                                }

                                if let previewURL = selectedPreviewURL {
                                    VideoPlayer(player: AVPlayer(url: previewURL))
                                        .frame(height: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }

                                PhotosPicker(
                                    selection: $selectedItem,
                                    matching: .videos,
                                    photoLibrary: .shared()
                                ) {
                                    Text(selectedVideo == nil ? "选择新视频" : "重新选择视频")
                                }
                                .buttonStyle(PetPalSecondaryButtonStyle())
                                .onChange(of: selectedItem) {
                                    Task {
                                        await loadSelectedVideo()
                                    }
                                }

                                if selectedVideo != nil {
                                    Button {
                                        Task {
                                            await replaceVideo()
                                        }
                                    } label: {
                                        Group {
                                            if isUploading {
                                                ProgressView()
                                                    .tint(.white)
                                            } else {
                                                Text("上传更新")
                                            }
                                        }
                                    }
                                    .buttonStyle(PetPalPrimaryButtonStyle())
                                    .disabled(
                                        isUploading ||
                                        appStore.session.userId == nil ||
                                        appStore.session.petId == nil
                                    )
                                }

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(PetPalTheme.danger)
                                }
                            }
                        }

                        PetPalPanelCard {
                            PetPalSectionHeader(
                                eyebrow: "通用",
                                title: "重置当前配置",
                                chipText: nil
                            )

                            Button("重置当前配置", role: .destructive) {
                                isShowingResetConfirmation = true
                            }
                            .buttonStyle(PetPalDangerButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
                .safeAreaPadding(.top, 12)
                .scrollBounceBehavior(.basedOnSize)

                if isUploading {
                    PetPalLoadingOverlay(
                        title: "正在更新联调视频...",
                        subtitle: "新的摄像头上下文会在上传完成后立即生效。"
                    )
                }
            }
        }
        .alert("确认重置当前配置？", isPresented: $isShowingResetConfirmation) {
            Button("确认重置", role: .destructive) {
                appStore.reset()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清空当前宠物和摄像头相关配置。")
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var selectedPreviewURL: URL? {
        if let selectedVideo {
            return selectedVideo.url
        }

        return appStore.apiClient.resolvedURL(for: appStore.session.demoVideoURL)
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
                    cameraName: appStore.session.cameraName.ifEmpty("家庭摄像头"),
                    cameraID: appStore.session.cameraId,
                    videoFileURL: selectedVideo.url
                )
            )
            appStore.applyUploadedDemoVideo(response)
            self.selectedVideo = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isUploading = false
    }
}

private struct PetPalDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(
                LinearGradient(
                    colors: [Color(hex: "D78172"), Color(hex: "C66B5F")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
