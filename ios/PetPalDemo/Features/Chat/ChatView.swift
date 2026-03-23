import AVFoundation
import AVKit
import Foundation
import PhotosUI
import SwiftUI
import UserNotifications

struct ChatView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var voicePlayback = VoicePlaybackController()
    @State private var draft = ""
    @State private var messages: [ChatMessage] = []
    @State private var isSubmitting = false
    @State private var isCameraPanelExpanded = false
    @State private var selectedContextVideoItem: PhotosPickerItem?
    @State private var selectedPreviewVideo: PickedVideo?
    @State private var latestCameraSummary: String?
    @State private var isUploadingContextVideo = false
    @State private var errorMessage: String?
    @State private var cameraPanelErrorMessage: String?
    @State private var healthAlerts: [HealthAlert] = []
    @State private var dailyReport: DailyReportResponse?
    @State private var anxietyReport: AnxietyResponse?
    @State private var inputMode: ChatInputMode = .text
    @State private var voiceCaptureState: VoiceCaptureState = .idle
    @State private var recordingStartedAt: Date?
    @State private var recordingElapsedSeconds = 0
    @State private var recordingTimer: Timer?
    @State private var hasLoadedInitialMessages = false
    @State private var expandedRelatedEventKey: RelatedEventExpansionKey?
    @State private var relatedEventClipStates: [Int: RelatedEventClipState] = [:]

    private let mockStatusEvents: [PetStatusEvent] = [
        .init(id: 1, minutesAgo: 5, eventText: "跑酷中"),
        .init(id: 2, minutesAgo: 10, eventText: "拉粑粑"),
        .init(id: 3, minutesAgo: 25, eventText: "喝完水在舔嘴"),
        .init(id: 4, minutesAgo: 59, eventText: "趴窗边看鸟"),
        .init(id: 5, minutesAgo: 60, eventText: "在窝里打盹"),
        .init(id: 6, minutesAgo: 300, eventText: "把玩具叼回来了"),
        .init(id: 7, minutesAgo: 301, eventText: "在门口发呆")
    ]

    var body: some View {
        PetPalShell {
            VStack(spacing: 0) {
                PetPalChatHeader(
                    avatar: petAvatar,
                    avatarImageURL: petAvatarImageURL,
                    title: appStore.session.petName.ifEmpty("PetPal"),
                    statusLines: petStatusLines,
                    subtitle: "在线"
                ) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .black))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(PetPalSmallGhostButtonStyle())
                    .accessibilityLabel("打开设置")
                }

                CameraContextPanel(
                    isExpanded: $isCameraPanelExpanded,
                    selectedVideoItem: $selectedContextVideoItem,
                    previewURL: cameraPreviewURL,
                    cameraName: cameraContextName,
                    statusText: cameraPanelStatusText,
                    detailText: cameraPanelDetailText,
                    videoName: appStore.session.demoVideoName.ifEmpty("未上传上下文视频"),
                    isUploading: isUploadingContextVideo,
                    errorMessage: cameraPanelErrorMessage,
                    onToggle: toggleCameraPanel
                )
                .padding(.horizontal, 18)
                .padding(.top, 12)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                messageRow(message)
                            }

                            if isSubmitting {
                                HStack(alignment: .top, spacing: 8) {
                                    chatAvatar

                                    HStack(spacing: 5) {
                                        Circle().fill(Color(hex: "B79F8E")).frame(width: 8, height: 8)
                                        Circle().fill(Color(hex: "B79F8E")).frame(width: 8, height: 8)
                                        Circle().fill(Color(hex: "B79F8E")).frame(width: 8, height: 8)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 16)
                                    .background(Color(hex: "FFF7EF"))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(Color(hex: "E8D5C1").opacity(0.7), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
                            }

                            if let errorMessage {
                                PetPalSurfaceCard {
                                    Text(errorMessage)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(PetPalTheme.danger)
                                }
                            }

                            if !healthAlerts.isEmpty {
                                PetPalPanelCard {
                                    sectionTitle(asset: .featureHealth, title: "身体状况报告")

                                    VStack(spacing: 8) {
                                        ForEach(healthAlerts, id: \.self) { alert in
                                            HStack(alignment: .top, spacing: 10) {
                                                PetPalArtImage(asset: PetPalArtAsset.healthAlert(for: alert.level))
                                                    .frame(width: 26, height: 26)

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(alert.title)
                                                        .font(.system(size: 15, weight: .black, design: .rounded))
                                                        .foregroundStyle(PetPalTheme.ink)

                                                    Text(alert.message)
                                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                                        .foregroundStyle(PetPalTheme.inkSoft)
                                                        .lineSpacing(3)
                                                }
                                            }
                                            .padding(14)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(alertBackground(alert.level))
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        }
                                    }
                                }
                            }

                            if let dailyReport {
                                DailyReportCardView(
                                    report: dailyReport,
                                    avatarAsset: petAvatar,
                                    avatarImageURL: petAvatarImageURL
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            if let anxietyReport {
                                PetPalPanelCard {
                                    sectionTitle(asset: .featureAnxiety, title: "分离焦虑指数")

                                    VStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                                .fill(anxietyBackground(anxietyReport.level))
                                                .frame(width: 88, height: 88)

                                            Text("\(anxietyReport.score)")
                                                .font(.system(size: 30, weight: .black, design: .rounded))
                                                .foregroundStyle(anxietyForeground(anxietyReport.level))
                                        }

                                        Text(anxietyReport.comment)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(PetPalTheme.ink)
                                            .multilineTextAlignment(.center)

                                        VStack(spacing: 12) {
                                            HStack(spacing: 12) {
                                                metricCard(title: "等你次数", value: "\(anxietyReport.waitingCount) 次")
                                                metricCard(
                                                    title: "累计等候",
                                                    value: "\(formatMinutes(anxietyReport.totalWaitingMinutes)) 分钟"
                                                )
                                            }

                                            HStack(spacing: 12) {
                                                metricCard(
                                                    title: "最长守门",
                                                    value: "\(formatMinutes(anxietyReport.longestWaitingMinutes)) 分钟"
                                                )
                                                metricCard(title: "守门占比", value: "\(anxietyReport.waitingSharePercent)%")
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 10)
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 20)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: messages.count, initial: true) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: isSubmitting) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: healthAlerts.count) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: dailyReport?.report ?? "") {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: anxietyReport?.score ?? -1) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                featureShortcutStrip
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color(hex: "FFFBF4").opacity(0.94))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: "E6D5C2").opacity(0.76))
                        .frame(height: 1)
                }

                inputBar
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color(hex: "FFFBF5").opacity(0.96))
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                voicePlayback.stop()
            }
        }
        .task {
            await loadInitialMessagesIfNeeded()
        }
        .onChange(of: selectedContextVideoItem) {
            Task {
                await importCameraVideo(from: selectedContextVideoItem)
            }
        }
        .onChange(of: speechRecognizer.isListening) {
            guard !speechRecognizer.isListening, voiceCaptureState == .recording else { return }
            recordingTimer?.invalidate()
            recordingTimer = nil
            recordingStartedAt = nil
            recordingElapsedSeconds = 0
            voiceCaptureState = .idle
            if let recognizerError = speechRecognizer.errorMessage {
                errorMessage = recognizerError
            }
        }
        .onDisappear {
            recordingTimer?.invalidate()
            _ = speechRecognizer.stopListening(discardRecording: true)
            voicePlayback.stop()
            cleanupVoiceMessageAudioFiles()
            cleanupSelectedPreviewVideo()
        }
    }

    // MARK: - Computed properties

    private var petAvatar: PetPalArtAsset {
        if let selectedAsset = PetPalArtAsset(rawValue: appStore.session.petDefaultAvatarAssetName) {
            return selectedAsset
        }

        return .pet(for: appStore.session.petSpecies)
    }

    private var petStatusLines: [String] {
        mockStatusEvents
            .filter { $0.minutesAgo <= 300 }
            .sorted { $0.minutesAgo < $1.minutesAgo }
            .map(\.displayLine)
    }

    private var petAvatarImageURL: URL? {
        let preferredPath = appStore.session.petAvatarURL.ifEmpty(appStore.session.petPhotoURL)
        return appStore.apiClient.resolvedURL(for: preferredPath)
    }

    private var cameraContextName: String {
        appStore.session.cameraName.ifEmpty("家庭摄像头")
    }

    private var cameraPreviewURL: URL? {
        if let selectedPreviewVideo {
            return selectedPreviewVideo.url
        }

        return appStore.apiClient.resolvedURL(for: appStore.session.demoVideoURL)
    }

    private var hasCameraContextVideo: Bool {
        cameraPreviewURL != nil
    }

    private var cameraPanelStatusText: String {
        if isUploadingContextVideo {
            return "正在解析新视频..."
        }

        if let cameraPanelErrorMessage {
            return cameraPanelErrorMessage
        }

        return latestCameraSummary
            ?? (hasCameraContextVideo
                ? "\(cameraContextName) 已接入"
                : "上传一段视频后，聊天会结合今天的画面。")
    }

    private var cameraPanelDetailText: String {
        if isUploadingContextVideo {
            return "解析完成后会立即更新到当前对话。"
        }

        if hasCameraContextVideo {
            return "点开可查看或更新当前视频。"
        }

        return "展开后可从系统相册选择一段视频。"
    }

    private var canSendMessage: Bool {
        !isSubmitting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTriggerPetSpeech: Bool {
        !isSubmitting && !isUploadingContextVideo && appStore.session.petId != nil && appStore.session.cameraId != nil && hasCameraContextVideo
    }

    private var isVoiceRecording: Bool {
        voiceCaptureState == .recording
    }

    private var isVoiceSending: Bool {
        voiceCaptureState == .sending
    }

    private var isVoiceInputDisabled: Bool {
        isSubmitting || isVoiceSending
    }

    private var chatAvatar: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "FFD8B5"), Color(hex: "F6BE95")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 34, height: 34)
            .overlay(
                PetPalImageFill(
                    imageURL: petAvatarImageURL,
                    fallbackAsset: petAvatar,
                    artSize: 18,
                    contentMode: .fill
                )
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .padding(3)
            )
            .padding(.top, 4)
    }

    private var petSpeechFeatureTitle: String {
        appStore.session.petSpecies == "dog" ? "汪言汪语" : "猫言猫语"
    }

    private var voiceCallShortcutChip: some View {
        Label("语音通话", systemImage: "phone.connection.fill")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(Color(hex: "194D49"))
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(
                LinearGradient(
                    colors: [Color(hex: "DFF6EF"), Color(hex: "BDE6DB"), Color(hex: "A5D9D0")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.58), lineWidth: 1)
            )
            .shadow(color: Color(hex: "7CB7A7").opacity(0.24), radius: 14, y: 8)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var featureShortcutStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                featureShortcutChip(
                    title: "健康告警",
                    systemImage: "cross.case.fill"
                ) {
                    await fetchHealthAlerts()
                }

                NavigationLink {
                    PetPalVoiceCallView(
                        petName: appStore.session.petName.ifEmpty("PetPal"),
                        cameraName: cameraContextName,
                        previewURL: cameraPreviewURL,
                        petAvatar: petAvatar,
                        petAvatarImageURL: petAvatarImageURL
                    )
                } label: {
                    voiceCallShortcutChip
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开语音通话")
                .accessibilityHint("进入陪伴摄像头语音通话页面")

                featureShortcutChip(
                    title: "每日简报",
                    systemImage: "sun.max.fill"
                ) {
                    await fetchDailyReport()
                }

                featureShortcutChip(
                    title: "焦虑指数",
                    systemImage: "chart.line.uptrend.xyaxis"
                ) {
                    await fetchAnxiety()
                }

                featureShortcutChip(
                    title: "宠物日记",
                    systemImage: "book.closed.fill"
                ) {
                    await fetchDiary()
                }

                Button {
                    Task {
                        await triggerProactiveVocalization()
                    }
                } label: {
                    Label(petSpeechFeatureTitle, systemImage: "message.badge.waveform")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(canTriggerPetSpeech ? Color.white : PetPalTheme.inkSoft)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(
                            canTriggerPetSpeech
                                ? AnyShapeStyle(PetPalTheme.chatUserGradient)
                                : AnyShapeStyle(Color(hex: "F5E8D7"))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canTriggerPetSpeech)
            }
            .padding(.trailing, 18)
        }
    }

    private func featureShortcutChip(
        title: String,
        systemImage: String,
        action: @escaping @Sendable () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color(hex: "FFF8EE").opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(PetPalTheme.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            leadingInputButton

            if inputMode == .text {
                TextField("和 \(appStore.session.petName.ifEmpty("宠物")) 聊聊天...", text: $draft)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(hex: "FFF7EE").opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(PetPalTheme.line, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityLabel("聊天输入框")

                Button {
                    Task {
                        await sendTextMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .black))
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(ChatSendButtonStyle())
                .disabled(!canSendMessage)
            } else {
                voiceHoldButton
            }
        }
    }

    private var leadingInputButton: some View {
        Button {
            if inputMode == .voice {
                switchToTextMode()
            } else {
                switchToVoiceMode()
            }
        } label: {
            Image(systemName: inputMode == .voice ? "keyboard.fill" : "mic.fill")
                .font(.system(size: 18, weight: .black))
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .background(inputMode == .voice ? Color(hex: "FFEAD8").opacity(0.95) : Color(hex: "FFF7EE").opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(inputMode == .voice ? Color(hex: "E8B27F").opacity(0.86) : PetPalTheme.line, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(isVoiceRecording || isVoiceSending)
        .accessibilityLabel(inputMode == .voice ? "切换到文字输入" : "切换到语音输入")
    }

    private var voiceHoldButton: some View {
        ZStack {
            if isVoiceRecording {
                HStack {
                    recordingPulse(side: .leading)
                    Spacer(minLength: 20)
                    recordingPulse(side: .trailing)
                }
                .padding(.horizontal, 24)
                .allowsHitTesting(false)
            }

            Text(voiceButtonTitle)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(isVoiceRecording ? .white : PetPalTheme.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(isVoiceRecording ? Color(hex: "E58A7F") : Color(hex: "FFF7EE").opacity(0.98))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isVoiceRecording ? Color(hex: "D46E63").opacity(0.92) : PetPalTheme.line,
                    lineWidth: 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .scaleEffect(isVoiceRecording ? 0.992 : 1)
        .animation(.easeOut(duration: 0.18), value: isVoiceRecording)
        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: 80, pressing: handleVoicePressChange) {}
        .accessibilityLabel(isVoiceRecording ? "正在录音" : "按住说话")
        .allowsHitTesting(!isVoiceInputDisabled || isVoiceRecording)
    }

    private var voiceButtonTitle: String {
        if isVoiceSending {
            return "发送中..."
        }

        if isVoiceRecording {
            return formattedDuration(recordingElapsedSeconds)
        }

        return "按住说话"
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if message.role == .assistant {
                    chatAvatar
                }

                if message.displayStyle == .voice, message.role == .user {
                    voiceMessageBubble(message)
                } else if message.messageType == .video {
                    proactiveVideoBubble(message)
                } else {
                    textMessageBubble(message)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant && !message.relatedEvents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("相关事件", systemImage: "paperclip")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .padding(.leading, 42)

                    ForEach(message.relatedEvents) { event in
                        relatedEventCard(event, messageID: message.id)
                            .padding(.leading, 42)
                    }
                }
            }
        }
    }

    private func textMessageBubble(_ message: ChatMessage) -> some View {
        Text(displayMessageContent(for: message))
            .font(
                message.role == .assistant
                    ? .system(size: 14, weight: .medium)
                    : .system(size: 14, weight: .medium, design: .rounded)
            )
            .foregroundStyle(message.role == .user ? .white : PetPalTheme.ink)
            .lineSpacing(4)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(message.role == .user ? AnyShapeStyle(PetPalTheme.chatUserGradient) : AnyShapeStyle(Color(hex: "FFF7EF")))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(message.role == .assistant ? Color(hex: "E8D5C1").opacity(0.7) : .clear, lineWidth: 1),
                alignment: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: 320, alignment: message.role == .user ? .trailing : .leading)
    }

    private func voiceMessageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button {
                handleVoiceBubbleTap(message)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: voicePlayback.playingMessageID == message.id ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("语音消息")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))

                        Text(formattedDuration(displayedVoiceDuration(for: message)))
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: 320, minHeight: 68, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "F09A7F"), Color(hex: "DA6F62")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(hex: "C86055").opacity(0.42), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Text((message.voiceTranscript ?? "").ifEmpty(message.content))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)
                .lineSpacing(3)
                .frame(maxWidth: 320, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
    }

    private func displayedVoiceDuration(for message: ChatMessage) -> Int {
        if voicePlayback.playingMessageID == message.id {
            return max(voicePlayback.remainingSeconds, 0)
        }

        return max(message.voiceDurationSeconds ?? 0, 0)
    }

    @ViewBuilder
    private func proactiveVideoBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 11, weight: .black))
                Text(petSpeechFeatureTitle)
                    .font(.system(size: 11, weight: .black, design: .rounded))
            }
            .foregroundStyle(Color(hex: "8A5A32"))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: "F7E8D6"))
            .clipShape(Capsule())

            Text(displayMessageContent(for: message))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PetPalTheme.ink)
                .lineSpacing(4)

            if let videoURL = appStore.apiClient.resolvedURL(for: message.mediaURL) {
                InlineVideoMessageView(url: videoURL)
                    .frame(width: 286, height: 184)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(12)
        .background(Color(hex: "FFF7EF"))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(hex: "E8D5C1").opacity(0.75), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func recordingPulse(side: PulseSide) -> some View {
        RecordingPulseView(isAnimating: isVoiceRecording, side: side)
    }

    // MARK: - Related event card

    private func relatedEventCard(_ event: RelatedEvent, messageID: String) -> some View {
        let eventKey = RelatedEventExpansionKey(messageID: messageID, eventID: event.id)
        let isExpanded = expandedRelatedEventKey == eventKey
        let videoURL = resolvedVideoURL(for: event)
        let clipState = relatedEventClipStates[event.id] ?? .idle

        return VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: eventIconName(event.eventType))
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(PetPalTheme.caramel)
                    .frame(width: 24, height: 24)
                    .background(Color(hex: "FFF7EE"))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.description.isEmpty ? "记录事件" : event.description)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)
                        .lineLimit(isExpanded ? nil : 1)

                    Text(formatEventTime(event.timestamp))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                }

                Spacer(minLength: 8)

                Button {
                    toggleRelatedEventExpansion(for: eventKey, eventID: event.id)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "play.rectangle.fill")
                            .font(.system(size: 11, weight: .black))

                        Text(relatedEventButtonTitle(isExpanded: isExpanded, clipState: clipState))
                            .font(.system(size: 11, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(isExpanded ? Color(hex: "7D5231") : Color(hex: "8F6543"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(isExpanded ? Color(hex: "F7E5D2") : Color(hex: "FFF7EE"))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "E2C7AD").opacity(isExpanded ? 0.9 : 0.65), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起事件视频" : "查看事件视频")
            }

            if isExpanded {
                if let videoURL {
                    InlineVideoMessageView(url: videoURL)
                        .frame(maxWidth: .infinity)
                        .frame(height: 184)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color(hex: "E5D2BF").opacity(0.72), lineWidth: 1)
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    relatedEventClipPlaceholder(for: clipState, eventID: event.id)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, isExpanded ? 14 : 12)
        .padding(.vertical, isExpanded ? 12 : 8)
        .background(isExpanded ? Color(hex: "FFF8F0") : Color(hex: "F5EDE3").opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: "E8D5C1").opacity(isExpanded ? 0.88 : 0.5), lineWidth: isExpanded ? 1.2 : 1)
        )
        .shadow(color: PetPalTheme.caramel.opacity(isExpanded ? 0.16 : 0), radius: isExpanded ? 14 : 0, y: isExpanded ? 8 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isExpanded)
    }

    private func eventIconName(_ type: String) -> String {
        switch type {
        case "eating": return "fork.knife"
        case "drinking": return "drop.fill"
        case "sleeping": return "moon.zzz.fill"
        case "playing": return "gamecontroller.fill"
        case "resting": return "sun.max.fill"
        case "waiting": return "clock.fill"
        case "litter_box": return "square.grid.2x2.fill"
        case "zoomies": return "bolt.fill"
        default: return "pin.fill"
        }
    }

    private func formatEventTime(_ isoString: String) -> String {
        // Extract HH:mm from ISO timestamp
        if let tIndex = isoString.firstIndex(of: "T") {
            let timePart = isoString[isoString.index(after: tIndex)...]
            let components = timePart.prefix(5)
            return String(components)
        }
        return isoString
    }

    private func toggleRelatedEventExpansion(for eventKey: RelatedEventExpansionKey, eventID: Int) {
        let shouldExpand = expandedRelatedEventKey != eventKey
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            expandedRelatedEventKey = shouldExpand ? eventKey : nil
        }

        guard shouldExpand else {
            return
        }

        Task {
            await loadRelatedEventClipIfNeeded(eventID: eventID)
        }
    }

    private func resolvedVideoURL(for event: RelatedEvent) -> URL? {
        if case .loaded(let loadedURL) = relatedEventClipStates[event.id] {
            return loadedURL
        }

        let clipPath = event.videoClipUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if let directClipURL = appStore.apiClient.resolvedURL(for: clipPath),
           isPlayableVideoURL(directClipURL) {
            return directClipURL
        }

        return nil
    }

    private func isPlayableVideoURL(_ url: URL) -> Bool {
        let videoExtensions = Set(["mp4", "mov", "m4v"])
        return videoExtensions.contains(url.pathExtension.lowercased())
    }

    private func relatedEventButtonTitle(isExpanded: Bool, clipState: RelatedEventClipState) -> String {
        if isExpanded {
            return "收起视频"
        }

        switch clipState {
        case .failed(_):
            return "重试片段"
        case .loading:
            return "生成中"
        case .loaded(_), .idle:
            return "查看视频"
        }
    }

    @ViewBuilder
    private func relatedEventClipPlaceholder(for clipState: RelatedEventClipState, eventID: Int) -> some View {
        switch clipState {
        case .loading, .idle:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(PetPalTheme.caramel)

                Text("正在生成事件片段...")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .padding(.horizontal, 14)
            .background(Color(hex: "FFF8F0"))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: "E5D2BF").opacity(0.72), lineWidth: 1)
            )
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.danger)
                    .lineSpacing(3)

                Button("重新生成片段") {
                    Task {
                        await loadRelatedEventClipIfNeeded(eventID: eventID, forceReload: true)
                    }
                }
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: "8F6543"))
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(hex: "FFF8F0"))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: "E5D2BF").opacity(0.72), lineWidth: 1)
            )
        case .loaded(_):
            EmptyView()
        }
    }

    @MainActor
    private func loadRelatedEventClipIfNeeded(eventID: Int, forceReload: Bool = false) async {
        if !forceReload {
            switch relatedEventClipStates[eventID] ?? .idle {
            case .loading, .loaded(_):
                return
            case .idle, .failed(_):
                break
            }
        }

        relatedEventClipStates[eventID] = .loading

        do {
            let response = try await appStore.apiClient.fetchEventClip(eventID: eventID)
            guard let clipURL = appStore.apiClient.resolvedURL(for: response.videoClipURL),
                  isPlayableVideoURL(clipURL) else {
                relatedEventClipStates[eventID] = .failed("生成了片段，但地址不可播放。")
                return
            }

            relatedEventClipStates[eventID] = .loaded(clipURL)
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            relatedEventClipStates[eventID] = .failed(message.ifEmpty("事件片段生成失败，请稍后重试。"))
        }
    }

    // MARK: - Subview builders

    private func sectionTitle(asset: PetPalArtAsset, title: String) -> some View {
        HStack(spacing: 8) {
            PetPalArtImage(asset: asset)
                .frame(width: 20, height: 20)

            Text(title)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)
        }
    }

    private func alertBackground(_ level: String) -> Color {
        switch level {
        case "critical":
            return PetPalTheme.alertCriticalBg.opacity(0.86)
        case "warning":
            return PetPalTheme.alertWarningBg.opacity(0.85)
        default:
            return PetPalTheme.alertSuccessBg.opacity(0.8)
        }
    }

    private func anxietyBackground(_ level: String) -> LinearGradient {
        switch level {
        case "high":
            return LinearGradient(colors: [Color(hex: "E58A7F"), Color(hex: "CB655B")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "moderate":
            return LinearGradient(colors: [Color(hex: "FFC893"), Color(hex: "EF986A")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "mild":
            return LinearGradient(colors: [Color(hex: "FFE7BA"), Color(hex: "F4C37D")], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return PetPalTheme.mintGradient
        }
    }

    private func anxietyForeground(_ level: String) -> Color {
        switch level {
        case "relaxed":
            return PetPalTheme.anxietyRelaxed
        case "mild":
            return PetPalTheme.anxietyMild
        default:
            return .white
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)

            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color(hex: "FFF8EE").opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func formatMinutes(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func openingLine(style: String, species: String, ownerAlias: String) -> String {
        let trimmedOwnerAlias = ownerAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasOwnerAlias = !trimmedOwnerAlias.isEmpty

        if style == "loyal" {
            return species == "dog"
                ? (hasOwnerAlias
                    ? "\(trimmedOwnerAlias)！我今天一直守着门口，终于等到你来找我啦！"
                    : "主人！我今天一直守着门口，终于等到你来找我啦！")
                : (hasOwnerAlias
                    ? "\(trimmedOwnerAlias)，我今天也有乖乖等你，快夸夸我。"
                    : "主人主人，我今天也有乖乖等你，快夸夸我。")
        }

        if style == "chatty" {
            return species == "dog"
                ? (hasOwnerAlias
                    ? "\(trimmedOwnerAlias)，你知道吗你知道吗，今天家里发生了好多事，我都记住了！"
                    : "你知道吗你知道吗，今天家里发生了好多事，我都记住了！")
                : (hasOwnerAlias
                    ? "\(trimmedOwnerAlias)，你终于来了，我今天从窗边看到好多小动静，想讲给你听。"
                    : "你终于来了，我今天从窗边看到好多小动静，想讲给你听。")
        }

        if style == "chill" {
            return hasOwnerAlias
                ? "\(trimmedOwnerAlias)，今天还算不错，阳光、零食和想你这件事都刚刚好。"
                : "今天还算不错，阳光、零食和想你这件事都刚刚好。"
        }

        return species == "dog"
            ? (hasOwnerAlias
                ? "哼，\(trimmedOwnerAlias)，我才不是特地在等你，只是刚好想和你说说今天的事。"
                : "哼，我才不是特地在等你，只是刚好想和你说说今天的事。")
            : (hasOwnerAlias
                ? "哼，\(trimmedOwnerAlias)，你终于想起来看我了？我今天在门口等了你好一会儿。"
                : "哼，你终于想起来看我了？我今天在门口等了你好一会儿。")
    }

    // MARK: - Actions

    private func switchToVoiceMode() {
        errorMessage = nil
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            inputMode = .voice
        }
    }

    private func switchToTextMode() {
        recordingTimer?.invalidate()
        voiceCaptureState = .idle
        recordingElapsedSeconds = 0
        recordingStartedAt = nil
        _ = speechRecognizer.stopListening(discardRecording: true)
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            inputMode = .text
        }
    }

    private func handleVoicePressChange(_ isPressing: Bool) {
        if isPressing {
            guard !isVoiceRecording, !isVoiceSending, !isSubmitting else { return }
            Task {
                await startVoiceCapture()
            }
        } else if isVoiceRecording {
            Task {
                await finishVoiceCapture()
            }
        }
    }

    private func displayMessageContent(for message: ChatMessage) -> String {
        guard message.role == .assistant else { return message.content }
        return message.content.petPalDisplaySanitized().ifEmpty(message.content)
    }

    private func startVoiceCapture() async {
        errorMessage = nil
        let authorized = await speechRecognizer.requestAuthorization()
        guard authorized else {
            errorMessage = speechRecognizer.errorMessage ?? "语音识别权限未授权"
            return
        }

        do {
            try speechRecognizer.startListening()
            recordingStartedAt = Date()
            recordingElapsedSeconds = 0
            voiceCaptureState = .recording
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    guard let recordingStartedAt else { return }
                    recordingElapsedSeconds = max(Int(Date().timeIntervalSince(recordingStartedAt).rounded(.down)), 0)
                }
            }
        } catch {
            errorMessage = speechRecognizer.errorMessage ?? error.localizedDescription
            voiceCaptureState = .idle
        }
    }

    private func finishVoiceCapture() async {
        guard isVoiceRecording else { return }

        voiceCaptureState = .sending
        recordingTimer?.invalidate()
        recordingTimer = nil

        let captureResult = speechRecognizer.stopListening()
        recordingStartedAt = nil
        recordingElapsedSeconds = 0

        let transcript = captureResult.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            if let audioFileURL = captureResult.audioFileURL {
                try? FileManager.default.removeItem(at: audioFileURL)
            }
            errorMessage = "未识别到有效内容，请再试一次。"
            voiceCaptureState = .idle
            return
        }

        let voiceMessage = ChatMessage(
            role: .user,
            content: transcript,
            displayStyle: .voice,
            voiceAudioURL: captureResult.audioFileURL,
            voiceDurationSeconds: max(captureResult.durationSeconds, 1),
            voiceTranscript: transcript
        )

        await sendMessage(userMessage: voiceMessage, backendMessage: transcript)
        voiceCaptureState = .idle
        inputMode = .voice
    }

    private func toggleCameraPanel() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isCameraPanelExpanded.toggle()
        }
    }

    private func importCameraVideo(from selectedItem: PhotosPickerItem?) async {
        cameraPanelErrorMessage = nil
        defer {
            selectedContextVideoItem = nil
        }

        guard let selectedItem else { return }

        do {
            guard let pickedVideo = try await selectedItem.loadTransferable(type: PickedVideo.self) else {
                cameraPanelErrorMessage = "无法读取你选择的视频，请重新试一次。"
                return
            }
            await uploadContextVideo(pickedVideo)
        } catch {
            cameraPanelErrorMessage = "读取相册视频失败：\(error.localizedDescription)"
        }
    }

    private func cleanupSelectedPreviewVideo() {
        guard let selectedPreviewVideo else { return }
        try? FileManager.default.removeItem(at: selectedPreviewVideo.url)
        self.selectedPreviewVideo = nil
    }

    private func uploadContextVideo(_ pickedVideo: PickedVideo) async {
        guard
            let userID = appStore.session.userId,
            let petID = appStore.session.petId
        else {
            cameraPanelErrorMessage = "当前会话信息不完整，暂时无法上传视频。"
            try? FileManager.default.removeItem(at: pickedVideo.url)
            return
        }

        isUploadingContextVideo = true
        cameraPanelErrorMessage = nil
        latestCameraSummary = nil

        do {
            let response = try await appStore.apiClient.uploadDemoVideo(
                DemoVideoUploadRequest(
                    userID: userID,
                    petID: petID,
                    cameraName: appStore.session.cameraName.ifEmpty("家庭摄像头"),
                    cameraID: appStore.session.cameraId,
                    videoFileURL: pickedVideo.url
                )
            )

            cleanupSelectedPreviewVideo()
            selectedPreviewVideo = pickedVideo
            latestCameraSummary = response.contextSummary
            appStore.applyUploadedDemoVideo(response)

            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isCameraPanelExpanded = true
            }
        } catch {
            try? FileManager.default.removeItem(at: pickedVideo.url)
            cameraPanelErrorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isUploadingContextVideo = false
    }

    private func sendTextMessage() async {
        await sendMessage(
            userMessage: ChatMessage(role: .user, content: draft.trimmingCharacters(in: .whitespacesAndNewlines)),
            backendMessage: draft
        )
        if !isSubmitting {
            draft = ""
        }
    }

    private func sendMessage(userMessage: ChatMessage, backendMessage: String) async {
        guard let petID = appStore.session.petId else { return }
        let trimmed = backendMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorMessage = nil
        isSubmitting = true
        clearFeaturePanels()
        messages.append(userMessage)

        // Create an empty assistant message for streaming
        let streamMessageID = UUID().uuidString
        messages.append(ChatMessage(id: streamMessageID, role: .assistant, content: ""))

        do {
            try await appStore.apiClient.sendChatStream(
                petID: petID,
                message: trimmed,
                onToken: { token in
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == streamMessageID }) {
                            messages[idx].content += token
                        }
                    }
                },
                onDone: { relatedEvents in
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == streamMessageID }) {
                            messages[idx].relatedEvents = relatedEvents
                        }
                    }
                }
            )
        } catch {
            // If streaming fails, remove the empty message and fall back to sync
            if let idx = messages.firstIndex(where: { $0.id == streamMessageID }) {
                messages.remove(at: idx)
            }
            do {
                let response = try await appStore.apiClient.sendChat(petID: petID, message: trimmed)
                messages.append(ChatMessage(role: .assistant, content: response.reply, relatedEvents: response.relatedEvents))
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }

        isSubmitting = false
    }

    private func handleVoiceBubbleTap(_ message: ChatMessage) {
        guard let audioURL = message.voiceAudioURL else { return }

        if voicePlayback.playingMessageID == message.id {
            voicePlayback.stop()
            return
        }

        let duration = max(message.voiceDurationSeconds ?? 0, 1)
        voicePlayback.play(messageID: message.id, audioURL: audioURL, durationSeconds: duration)
    }

    private func loadInitialMessagesIfNeeded() async {
        guard !hasLoadedInitialMessages else { return }
        hasLoadedInitialMessages = true

        guard let petID = appStore.session.petId else {
            messages = [openingAssistantMessage]
            return
        }

        do {
            let history = try await appStore.apiClient.fetchChatHistory(petID: petID)
            messages = history.isEmpty ? [openingAssistantMessage] : history
        } catch {
            messages = [openingAssistantMessage]
        }
    }

    private var openingAssistantMessage: ChatMessage {
        ChatMessage(
            role: .assistant,
            content: openingLine(
                style: appStore.session.languageStyle,
                species: appStore.session.petSpecies,
                ownerAlias: appStore.session.ownerAlias
            )
        )
    }

    private func triggerProactiveVocalization() async {
        guard let petID = appStore.session.petId, let cameraID = appStore.session.cameraId else {
            errorMessage = "请先上传一段陪伴视频，再试试这个功能。"
            return
        }

        errorMessage = nil
        clearFeaturePanels()
        isSubmitting = true

        do {
            let response = try await appStore.apiClient.triggerProactiveVocalization(
                petID: petID,
                cameraID: cameraID
            )
            messages.append(response.message)

            if response.matched {
                let notifications = PetPalLocalNotificationManager.shared
                let granted = await notifications.requestAuthorizationIfNeeded()
                if granted {
                    await notifications.deliverImmediately(
                        title: response.notificationTitle,
                        body: response.notificationBody
                    )
                }
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }

    private func cleanupVoiceMessageAudioFiles() {
        for message in messages {
            guard let audioURL = message.voiceAudioURL else { continue }
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let safeSeconds = max(totalSeconds, 0)
        return String(format: "%02d:%02d", safeSeconds / 60, safeSeconds % 60)
    }

    private func fetchDailyReport() async {
        guard let petID = appStore.session.petId else { return }
        errorMessage = nil
        isSubmitting = true
        clearFeaturePanels()
        messages.append(ChatMessage(role: .user, content: "给我看看你今天的简报吧"))

        do {
            let response = try await appStore.apiClient.fetchDailyReport(petID: petID)
            if response.card != nil {
                dailyReport = response
            } else {
                messages.append(ChatMessage(role: .assistant, content: response.report))
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }

    private func fetchDiary() async {
        guard let petID = appStore.session.petId else { return }
        await fetchTextAction(
            prompt: "我想看看你今天写下的心情",
            request: { try await appStore.apiClient.fetchDiary(petID: petID).diary }
        )
    }

    private func fetchHealthAlerts() async {
        guard let petID = appStore.session.petId else { return }
        errorMessage = nil
        isSubmitting = true
        clearFeaturePanels()
        messages.append(ChatMessage(role: .user, content: "你今天身体还好吗？"))

        do {
            let response = try await appStore.apiClient.fetchHealthAlerts(petID: petID)
            healthAlerts = response.alerts
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }

    private func fetchAnxiety() async {
        guard let petID = appStore.session.petId else { return }
        errorMessage = nil
        isSubmitting = true
        clearFeaturePanels()
        messages.append(ChatMessage(role: .user, content: "我不在家的时候，你是不是有点想我？"))

        do {
            anxietyReport = try await appStore.apiClient.fetchAnxiety(petID: petID)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }

    private func fetchTextAction(
        prompt: String,
        request: @escaping () async throws -> String
    ) async {
        errorMessage = nil
        isSubmitting = true
        clearFeaturePanels()
        messages.append(ChatMessage(role: .user, content: prompt))

        do {
            let content = try await request()
            messages.append(ChatMessage(role: .assistant, content: content))
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }

    private func clearFeaturePanels() {
        healthAlerts = []
        dailyReport = nil
        anxietyReport = nil
    }
}

private struct DailyReportCardView: View {
    let report: DailyReportResponse
    let avatarAsset: PetPalArtAsset
    let avatarImageURL: URL?

    @ScaledMetric(relativeTo: .headline) private var stampScale: CGFloat = 0.8

    private var card: DailyReportCard? {
        report.card
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        if let card {
            PetPalPanelCard {
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 8) {
                        PetPalArtImage(asset: .featureReport)
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)

                        Text("每日简报")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(PetPalTheme.ink)
                    }

                    Spacer(minLength: 8)

                    DailyReportMoodBadge(mood: card.mood)
                }

                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FFF0E0"), Color(hex: "FFE7D2")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color(hex: "E9CDB1").opacity(0.9), lineWidth: 1)
                        )

                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 94, height: 94)
                        .blur(radius: 8)
                        .offset(x: 18, y: -16)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.headline)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(PetPalTheme.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("今天的小日子，我都帮你记下来了。")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(PetPalTheme.caramel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .padding(.trailing, 70)

                    PetPalStamp(fallbackAsset: avatarAsset, imageURL: avatarImageURL)
                        .scaleEffect(stampScale)
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                        .accessibilityHidden(true)
                }

                Text(card.summary)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .lineSpacing(4)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if !card.activityTags.isEmpty {
                    DailyReportTagWrap(tags: card.activityTags)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    DailyReportMetricTile(title: "吃饭", value: "\(card.stats.eating) 次", systemImage: "fork.knife")
                    DailyReportMetricTile(title: "喝水", value: "\(card.stats.drinking) 次", systemImage: "drop.fill")
                    DailyReportMetricTile(title: "玩耍", value: "\(card.stats.playing) 次", systemImage: "gamecontroller.fill")
                    DailyReportMetricTile(title: "等门", value: "\(card.stats.waiting) 次", systemImage: "clock.fill")
                }

                Text(card.closingLine)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
        }
    }
}

private struct DailyReportMoodBadge: View {
    let mood: String

    private var foreground: Color {
        switch mood {
        case "松弛":
            return Color(hex: "567053")
        case "兴奋":
            return Color(hex: "915738")
        case "想你":
            return Color(hex: "8B514A")
        default:
            return PetPalTheme.caramel
        }
    }

    private var background: Color {
        switch mood {
        case "松弛":
            return Color(hex: "E6F2E7").opacity(0.96)
        case "兴奋":
            return Color(hex: "FFF1D9").opacity(0.96)
        case "想你":
            return Color(hex: "FCE4DE").opacity(0.96)
        default:
            return Color(hex: "FFF0DC").opacity(0.96)
        }
    }

    private var border: Color {
        switch mood {
        case "松弛":
            return Color(hex: "BFD7BF")
        case "兴奋":
            return Color(hex: "E8C695")
        case "想你":
            return Color(hex: "E6BCAF")
        default:
            return Color(hex: "E6C9AB")
        }
    }

    var body: some View {
        Text(mood)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(background)
            .overlay(
                Capsule()
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(Capsule())
            .accessibilityLabel("今日心情 \(mood)")
    }
}

private struct DailyReportMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(PetPalTheme.caramel)
                .frame(width: 28, height: 28)
                .background(Color(hex: "FFF3E4"))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)

                Text(value)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(hex: "FFF8EE").opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

private struct DailyReportTagWrap: View {
    let tags: [String]

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.caramel)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .background(Color(hex: "FFF1E2"))
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "E8D0B4"), lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今日行为标签")
    }
}

private struct CameraContextPanel: View {
    @Binding var isExpanded: Bool
    @Binding var selectedVideoItem: PhotosPickerItem?
    let previewURL: URL?
    let cameraName: String
    let statusText: String
    let detailText: String
    let videoName: String
    let isUploading: Bool
    let errorMessage: String?
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("陪伴摄像头")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)

                    Text(statusText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(errorMessage == nil ? PetPalTheme.inkSoft : PetPalTheme.danger)
                        .lineLimit(isExpanded ? 2 : 1)
                }

                Spacer(minLength: 8)

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(PetPalTheme.ink)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "FFF4E7"))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起摄像头浮层" : "展开摄像头浮层")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    PhotosPicker(
                        selection: $selectedVideoItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "FFF7EE"), Color(hex: "F3ECE0")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            CameraContextPreview(previewURL: previewURL)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .padding(6)

                            PetPalCapsuleLabel(text: cameraName, style: .context)
                                .padding(16)

                            if isUploading {
                                VStack(spacing: 10) {
                                    ProgressView()
                                        .controlSize(.large)
                                        .tint(.white)

                                    Text("正在解析上传视频")
                                        .font(.system(size: 14, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("完成后会立即更新聊天上下文")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.88))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.black.opacity(0.32))
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .padding(6)
                            }
                        }
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(PetPalTheme.line.opacity(0.9), lineWidth: 1.2)
                        )
                        .shadow(color: PetPalTheme.caramel.opacity(0.12), radius: 18, y: 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploading)
                    .accessibilityLabel("选择摄像头视频")
                    .accessibilityHint("从系统相册选择一段视频来更新聊天上下文")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(videoName)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(PetPalTheme.ink)
                            .lineLimit(1)

                        Text(detailText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(PetPalTheme.inkSoft)
                            .lineSpacing(3)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(PetPalTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.82), lineWidth: 1)
        )
        .shadow(color: PetPalTheme.caramel.opacity(0.1), radius: 14, y: 8)
        .animation(.easeOut(duration: 0.22), value: isUploading)
    }
}

private struct CameraContextPreview: View {
    let previewURL: URL?

    var body: some View {
        ZStack {
            if let previewURL {
                PetPalPlayableVideoView(url: previewURL)
                    .overlay(alignment: .bottomTrailing) {
                        Label("重选视频", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.28))
                            .clipShape(Capsule())
                            .padding(14)
                    }
            } else {
                mockCameraPreview
            }
        }
    }

    private var mockCameraPreview: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "E8DED0"), Color(hex: "D5E2DB"), Color(hex: "F5E6D8")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.42))
                .frame(width: 110, height: 110)
                .blur(radius: 8)
                .offset(x: -70, y: -36)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.66))
                .frame(width: 164, height: 88)
                .offset(x: -52, y: 20)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(hex: "FFF9F2").opacity(0.92))
                .frame(width: 106, height: 64)
                .offset(x: 76, y: -14)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "EC7E6D"))
                        .frame(width: 9, height: 9)

                    Text("LIVE MOCK")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.22))
                .clipShape(Capsule())

                Label("点击上传视频", systemImage: "video.badge.plus")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)

                Text("从系统相册选择一段视频作为今天的上下文。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 28)
            }
        }
    }
}

private struct ChatSendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(PetPalTheme.chatUserGradient)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

private enum ChatInputMode {
    case text
    case voice
}

private enum VoiceCaptureState {
    case idle
    case recording
    case sending
}

private enum PulseSide {
    case leading
    case trailing
}

@MainActor
private final class VoicePlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingMessageID: String?
    @Published private(set) var remainingSeconds = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play(messageID: String, audioURL: URL, durationSeconds: Int) {
        stop()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.delegate = self
            player.prepareToPlay()
            player.play()

            self.player = player
            self.playingMessageID = messageID
            self.remainingSeconds = durationSeconds

            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.syncRemainingTime()
                }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        playingMessageID = nil
        remainingSeconds = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }

    private func syncRemainingTime() {
        guard let player else {
            stop()
            return
        }

        let remaining = max(Int(ceil(player.duration - player.currentTime)), 0)
        remainingSeconds = remaining
        if remaining <= 0 || !player.isPlaying {
            stop()
        }
    }
}

@MainActor
private final class PetPalLocalNotificationManager {
    static let shared = PetPalLocalNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private var hasRequestedAuthorization = false

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            hasRequestedAuthorization = true
            return true
        case .denied:
            hasRequestedAuthorization = true
            return false
        case .notDetermined:
            guard !hasRequestedAuthorization else { return false }
            hasRequestedAuthorization = true
            return await requestAuthorization()
        @unknown default:
            return false
        }
    }

    func deliverImmediately(title: String, body: String) async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "petpal-proactive-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }
}

private struct InlineVideoMessageView: View {
    let url: URL

    var body: some View {
        PetPalPlayableVideoView(url: url)
            .background(Color.black.opacity(0.08))
    }
}

private struct PetPalVoiceCallView: View {
    @Environment(\.dismiss) private var dismiss

    let petName: String
    let cameraName: String
    let previewURL: URL?
    let petAvatar: PetPalArtAsset
    let petAvatarImageURL: URL?

    @State private var isMuted = false
    @State private var isSpeakerOn = true
    @State private var callStartedAt = Date()
    @State private var elapsedSeconds = 0
    @State private var callTimer: Timer?
    @State private var controlsAreVisible = false
    @State private var livePulseVisible = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                voiceCallBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    monitorStage(height: max(proxy.size.height * 0.6, 360))
                    Spacer(minLength: 0)
                }

                topBar

                bottomControls
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .statusBarHidden()
        .onAppear {
            startCallTimerIfNeeded()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.88).delay(0.05)) {
                controlsAreVisible = true
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                livePulseVisible = true
            }
        }
        .onDisappear {
            stopCallTimer()
        }
    }

    private var voiceCallBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "2B2525"), Color(hex: "171417"), Color(hex: "120F13")],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color(hex: "F4A774").opacity(0.32), .clear],
                center: UnitPoint(x: 0.16, y: 0.14),
                startRadius: 10,
                endRadius: 260
            )

            RadialGradient(
                colors: [Color(hex: "9DD6C9").opacity(0.28), .clear],
                center: UnitPoint(x: 0.84, y: 0.12),
                startRadius: 12,
                endRadius: 250
            )

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func monitorStage(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Group {
                if let previewURL {
                    LoopingVideoPlayerView(url: previewURL)
                } else {
                    VoiceCallMockMonitorView(cameraName: cameraName)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.12), Color.black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 24, y: 14)
            .padding(.horizontal, 14)
            .padding(.top, 18)

            VStack(spacing: 16) {
                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FFD8B5"), Color(hex: "F6BE95")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            PetPalImageFill(
                                imageURL: petAvatarImageURL,
                                fallbackAsset: petAvatar,
                                artSize: 24,
                                contentMode: .fill
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(4)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(petName) 正在陪伴通话")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text(cameraName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.74))
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    liveBadge

                    Label("陪伴中", systemImage: "waveform")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
        }
        .frame(height: height)
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回聊天")

                Spacer(minLength: 12)

                Text("语音通话")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer(minLength: 12)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(width: 56, alignment: .trailing)
                }
                .accessibilityLabel("当前时间")
            }
            .padding(.horizontal, 20)
            .safeAreaPadding(.top, 8)

            Spacer()
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 22) {
                Text(formattedCallDuration(elapsedSeconds))
                    .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(PetPalTheme.ink)
                    .accessibilityLabel("通话时长 \(formattedCallDurationForAccessibility(elapsedSeconds))")

                Text("通话连接稳定，监控画面已同步")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)

                HStack(alignment: .top, spacing: 24) {
                    VoiceCallActionButton(
                        title: "静音",
                        systemImage: isMuted ? "mic.slash.fill" : "mic.fill",
                        accentColor: Color(hex: "F0B98B"),
                        isActive: isMuted,
                        statusText: isMuted ? "已开启" : "已关闭",
                        accessibilityLabel: "静音，\(isMuted ? "已开启" : "已关闭")"
                    ) {
                        isMuted.toggle()
                    }

                    VStack(spacing: 10) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 22, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 74, height: 74)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "E77964"), Color(hex: "CF6A5A")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Circle())
                                .shadow(color: Color(hex: "A83D37").opacity(0.36), radius: 18, y: 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("挂断通话")

                        Text("挂断")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(PetPalTheme.ink)
                    }

                    VoiceCallActionButton(
                        title: "免提",
                        systemImage: isSpeakerOn ? "speaker.wave.3.fill" : "speaker.slash.fill",
                        accentColor: Color(hex: "9CD4C8"),
                        isActive: isSpeakerOn,
                        statusText: isSpeakerOn ? "已开启" : "已关闭",
                        accessibilityLabel: "免提，\(isSpeakerOn ? "已开启" : "已关闭")"
                    ) {
                        isSpeakerOn.toggle()
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .background(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color(hex: "FFF8EF").opacity(0.94))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.white.opacity(0.46), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 28, y: 14)
            .padding(.horizontal, 14)
            .safeAreaPadding(.bottom, 10)
            .offset(y: controlsAreVisible ? 0 : 28)
            .opacity(controlsAreVisible ? 1 : 0)
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: "FF7B6A"))
                .frame(width: 10, height: 10)
                .scaleEffect(livePulseVisible ? 1 : 0.72)
                .opacity(livePulseVisible ? 0.96 : 0.55)

            Text("LIVE")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("实时监控中")
    }

    private func startCallTimerIfNeeded() {
        guard callTimer == nil else { return }
        callStartedAt = .now
        elapsedSeconds = 0

        callTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                elapsedSeconds = max(Int(Date().timeIntervalSince(callStartedAt)), 0)
            }
        }
    }

    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
    }
}

private struct VoiceCallActionButton: View {
    let title: String
    let systemImage: String
    let accentColor: Color
    let isActive: Bool
    let statusText: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isActive ? accentColor.opacity(0.24) : Color(hex: "F3E5D7"))
                        .frame(width: 64, height: 64)

                    Circle()
                        .stroke(isActive ? accentColor.opacity(0.45) : PetPalTheme.line.opacity(0.8), lineWidth: 1)
                        .frame(width: 64, height: 64)

                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(isActive ? PetPalTheme.ink : PetPalTheme.inkSoft)
                }

                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)

                Text(statusText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
            }
            .frame(width: 92)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct VoiceCallMockMonitorView: View {
    let cameraName: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "2E3435"), Color(hex: "54625E"), Color(hex: "8B6C60")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 210, height: 210)
                .blur(radius: 12)
                .offset(x: -92, y: -108)

            Circle()
                .fill(Color(hex: "B6E1D8").opacity(0.2))
                .frame(width: 240, height: 240)
                .blur(radius: 14)
                .offset(x: 110, y: -82)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: 210, height: 110)
                .offset(x: -54, y: 64)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(hex: "FFF9F2").opacity(0.16))
                .frame(width: 132, height: 82)
                .offset(x: 92, y: 8)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 14, weight: .black))
                    Text("实时监控模拟画面")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.black.opacity(0.24))
                .clipShape(Capsule())

                Text(cameraName)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("未检测到今日视频，先以陪伴摄像头 mock 画面代替。")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("客厅机位")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.82))

                        Text("Signal 98%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.58))
                    }

                    Spacer()

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(context.date, format: .dateTime.hour().minute().second())
                            .font(.system(size: 11, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .accessibilityHidden(true)
                }
                .padding(18)

                Spacer()
            }

            VStack(spacing: 18) {
                ForEach(0..<7, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cameraName) 的模拟监控画面")
    }
}

private struct LoopingVideoPlayerView: View {
    @StateObject private var controller: LoopingVideoPlayerController

    init(url: URL) {
        _controller = StateObject(wrappedValue: LoopingVideoPlayerController(url: url))
    }

    var body: some View {
        VideoPlayer(player: controller.player)
            .allowsHitTesting(false)
            .onAppear {
                controller.play()
            }
            .onDisappear {
                controller.stop()
            }
    }
}

@MainActor
private final class LoopingVideoPlayerController: ObservableObject {
    let player: AVQueuePlayer

    private var looper: AVPlayerLooper?

    init(url: URL) {
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
    }

    func play() {
        player.play()
    }

    func stop() {
        player.pause()
        player.seek(to: .zero)
    }
}

private func formattedCallDuration(_ elapsedSeconds: Int) -> String {
    let minutes = elapsedSeconds / 60
    let seconds = elapsedSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

private func formattedCallDurationForAccessibility(_ elapsedSeconds: Int) -> String {
    let minutes = elapsedSeconds / 60
    let seconds = elapsedSeconds % 60

    if minutes == 0 {
        return "\(seconds) 秒"
    }

    if seconds == 0 {
        return "\(minutes) 分钟"
    }

    return "\(minutes) 分 \(seconds) 秒"
}

private struct RelatedEventExpansionKey: Hashable {
    let messageID: String
    let eventID: Int
}

private enum RelatedEventClipState: Equatable {
    case idle
    case loading
    case loaded(URL)
    case failed(String)
}

private struct RecordingPulseView: View {
    let isAnimating: Bool
    let side: PulseSide
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.26), lineWidth: 2)
                .frame(width: 26, height: 26)
                .scaleEffect(animate ? 1.9 : 0.7)
                .opacity(animate ? 0 : 0.9)

            Circle()
                .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                .frame(width: 18, height: 18)
                .scaleEffect(animate ? 1.45 : 0.78)
                .opacity(animate ? 0 : 0.85)

            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 8, height: 8)
        }
        .frame(width: 34, height: 34)
        .onAppear {
            guard isAnimating else { return }
            animatePulse()
        }
        .onChange(of: isAnimating) {
            if isAnimating {
                animatePulse()
            } else {
                animate = false
            }
        }
        .offset(x: side == .leading ? -2 : 2)
    }

    private func animatePulse() {
        animate = false
        withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
            animate = true
        }
    }
}

private extension String {
    func petPalDisplaySanitized() -> String {
        let filteredScalars = unicodeScalars.filter { scalar in
            let value = scalar.value

            if scalar == "\u{FFFD}" {
                return false
            }

            switch value {
            case 0x1F000...0x1FAFF,
                 0x2600...0x27BF,
                 0x200B...0x200F,
                 0x202A...0x202E,
                 0x2060...0x206F,
                 0xFE00...0xFE0F:
                return false
            case 0..<32:
                return scalar == "\n" || scalar == "\t"
            default:
                return true
            }
        }

        var cleaned = String(String.UnicodeScalarView(filteredScalars))
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "...", with: "……")
        cleaned = cleaned.replacingOccurrences(
            of: #"[（(][^()（）\n]{1,24}[）)]"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(of: #"！{2,}"#, with: "！", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"？{2,}"#, with: "？", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"～{2,}"#, with: "～", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n")
    }
}

private struct PetStatusEvent: Identifiable, Hashable {
    let id: Int
    let minutesAgo: Int
    let eventText: String

    var displayLine: String {
        "\(relativeTimeText) \(eventText)"
    }

    private var relativeTimeText: String {
        if minutesAgo < 60 {
            return "\(minutesAgo) 分钟前"
        }

        return "\(minutesAgo / 60) 小时前"
    }
}
