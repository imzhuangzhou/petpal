import AVKit
import PhotosUI
import SwiftUI

struct DemoVideoUploadView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var cameraName = "客厅摄像头"
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedVideo: PickedVideo?
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        PetPalShell {
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        PetPalStepIndicator(total: 2, current: 1)

                        PetPalHeroCard(
                            badge: "Demo context",
                            stamp: "🎞️",
                            title: "上传一段演示视频",
                            subtitle: "当前版本会基于视频生成 mock 行为数据，但后续聊天、简报、日记和告警都会围绕这段视频的上下文展开。"
                        )

                        PetPalPanelCard {
                            PetPalSectionHeader(
                                eyebrow: "上下文来源",
                                title: "给这只宠物绑定今天的“回家回放”",
                                chipText: "Step 4"
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                Text("展示名称")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(PetPalTheme.inkSoft)

                                TextField("", text: $cameraName)
                                    .petPalTextFieldStyle()
                            }

                            PhotosPicker(
                                selection: $selectedItem,
                                matching: .videos,
                                photoLibrary: .shared()
                            ) {
                                VStack(spacing: 10) {
                                    Text("📼")
                                        .font(.system(size: 34))

                                    Text(selectedVideo == nil ? "选择一段演示视频" : "重新选择视频")
                                        .font(.system(size: 18, weight: .black, design: .rounded))
                                        .foregroundStyle(PetPalTheme.ink)

                                    Text("推荐上传 10 秒以上的家庭宠物片段，后续可在设置中替换。")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(PetPalTheme.inkSoft)
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(3)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                                .padding(.horizontal, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(hex: "FFF9F1"), Color(hex: "FFF2E2")],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                                        .stroke(PetPalTheme.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("从系统照片中选择一个演示视频")
                            .onChange(of: selectedItem) {
                                Task {
                                    await loadSelectedVideo()
                                }
                            }

                            PetPalSurfaceCard {
                                Text("当前已绑定：\(selectedVideo?.url.lastPathComponent ?? appStore.session.demoVideoName.ifEmpty("暂未选择"))")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(PetPalTheme.ink)
                            }

                            if let selectedVideo {
                                PetPalSurfaceCard {
                                    HStack {
                                        PetPalCapsuleLabel(text: "今日上下文视频", style: .videoTag)
                                        Spacer(minLength: 8)
                                        Text(selectedVideo.url.lastPathComponent)
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundStyle(PetPalTheme.inkSoft)
                                            .lineLimit(1)
                                    }

                                    VideoPlayer(player: AVPlayer(url: selectedVideo.url))
                                        .frame(height: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                            }

                            Text("真正的摄像头绑定将在下一版补齐；这次先把视频上传、上下文建模、聊天体验和设置替换流程做成真实产品逻辑。")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(PetPalTheme.inkSoft)
                                .lineSpacing(3)
                                .padding(.top, 2)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(PetPalTheme.danger)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }

                if isUploading {
                    PetPalLoadingOverlay(
                        title: "正在建立今天的行为上下文...",
                        subtitle: "我们会根据你上传的视频生成可聊天的今日记录。"
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                Button {
                    Task {
                        await uploadVideo()
                    }
                } label: {
                    Text("上传并进入主页")
                }
                .buttonStyle(PetPalPrimaryButtonStyle())
                .disabled(
                    isUploading ||
                    appStore.session.userId == nil ||
                    appStore.session.petId == nil ||
                    selectedVideo == nil
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(
                LinearGradient(
                    colors: [
                        PetPalTheme.cream0.opacity(0),
                        PetPalTheme.cream0.opacity(0.96),
                        PetPalTheme.cream0
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
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
