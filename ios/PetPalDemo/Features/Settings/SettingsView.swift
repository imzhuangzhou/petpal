import AVKit
import PhotosUI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedVideo: PickedVideo?
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        PetPalShell {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Button {
                                dismiss()
                            } label: {
                                Text("← 返回")
                            }
                            .buttonStyle(PetPalSmallGhostButtonStyle())

                            Spacer(minLength: 0)

                            Text("设置")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(PetPalTheme.ink)

                            Spacer(minLength: 0)

                            Color.clear
                                .frame(width: 72, height: 1)
                        }
                        .padding(.top, 16)

                        PetPalHeroCard(
                            badge: "Profile",
                            stamp: petAvatar,
                            stampImageURL: petAvatarImageURL,
                            title: appStore.session.petName.ifEmpty("PetPal"),
                            subtitle: "主人是 \(appStore.session.nickname.ifEmpty("你"))，当前宠物种类为 \(appStore.session.petSpecies == "dog" ? "狗狗" : "猫咪")。"
                        )

                        PetPalPanelCard {
                            PetPalSectionHeader(
                                eyebrow: "声音配置",
                                title: "当前聊天会使用的宠物声音画像",
                                chipText: nil
                            )

                            PetPalSurfaceCard {
                                PetPalInfoRow(
                                    title: "当前模式",
                                    value: appStore.session.voiceType == "clone" ? "真实宠物原声" : "预设宠物声音"
                                )
                                PetPalInfoRow(
                                    title: "声音名称",
                                    value: appStore.session.voiceLabel.ifEmpty("未设置")
                                )

                                if !appStore.session.voiceSampleURL.isEmpty {
                                    Divider()
                                        .overlay(PetPalTheme.line.opacity(0.8))

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("已保存的真实宠物原声")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(PetPalTheme.ink)

                                        Text(appStore.apiClient.resolvedURL(for: appStore.session.voiceSampleURL)?.absoluteString ?? appStore.session.voiceSampleURL)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(PetPalTheme.inkSoft)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }

                        PetPalPanelCard {
                            PetPalSectionHeader(
                                eyebrow: "摄像头配置",
                                title: "当前绑定的家庭摄像头",
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
                                    Text("待更新联调视频：\(selectedVideo.url.lastPathComponent)")
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
                                    Text(selectedVideo == nil ? "选择联调视频" : "重新选择联调视频")
                                }
                                .buttonStyle(PetPalSecondaryButtonStyle())
                                .onChange(of: selectedItem) {
                                    Task {
                                        await loadSelectedVideo()
                                    }
                                }

                                Button {
                                    Task {
                                        await replaceVideo()
                                    }
                                } label: {
                                    Group {
                                        if isUploading {
                                            ProgressView()
                                                .tint(PetPalTheme.ink)
                                        } else {
                                            Text("上传并更新联调视频")
                                        }
                                    }
                                }
                                .buttonStyle(PetPalSecondaryButtonStyle())
                                .disabled(
                                    isUploading ||
                                    appStore.session.userId == nil ||
                                    appStore.session.petId == nil ||
                                    selectedVideo == nil
                                )

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
                                title: "重新开始配置",
                                chipText: nil
                            )

                            Text("如果你想重新创建宠物档案、重新录声音或重新绑定家庭摄像头，可以从这里回到起点。")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(PetPalTheme.inkSoft)
                                .lineSpacing(3)

                            Button("重置所有应用数据", role: .destructive) {
                                appStore.reset()
                                dismiss()
                            }
                            .buttonStyle(PetPalDangerButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }

                if isUploading {
                    PetPalLoadingOverlay(
                        title: "正在更新联调视频...",
                        subtitle: "新的摄像头上下文会在上传完成后立即生效。"
                    )
                }
            }
        }
    }

    private var petAvatar: String {
        appStore.session.petSpecies == "dog" ? "🐶" : "🐱"
    }

    private var petAvatarImageURL: URL? {
        let preferredPath = appStore.session.petAvatarURL.ifEmpty(appStore.session.petPhotoURL)
        return appStore.apiClient.resolvedURL(for: preferredPath)
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
