import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers
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
    @State private var isVideoImporterPresented = false
    @State private var selectedPreviewVideo: PickedVideo?
    @State private var latestCameraSummary: String?
    @State private var isUploadingContextVideo = false
    @State private var errorMessage: String?
    @State private var cameraPanelErrorMessage: String?
    @State private var healthAlerts: [HealthAlert] = []
    @State private var anxietyReport: AnxietyResponse?
    @State private var isFeatureMenuPresented = false
    @State private var inputMode: ChatInputMode = .text
    @State private var voiceCaptureState: VoiceCaptureState = .idle
    @State private var recordingStartedAt: Date?
    @State private var recordingElapsedSeconds = 0
    @State private var recordingTimer: Timer?
    @State private var hasLoadedInitialMessages = false

    var body: some View {
        PetPalShell {
            VStack(spacing: 0) {
                PetPalChatHeader(
                    avatar: petAvatar,
                    avatarImageURL: petAvatarImageURL,
                    title: appStore.session.petName.ifEmpty("PetPal"),
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
                    previewURL: cameraPreviewURL,
                    cameraName: cameraContextName,
                    statusText: cameraPanelStatusText,
                    detailText: cameraPanelDetailText,
                    videoName: appStore.session.demoVideoName.ifEmpty("未上传上下文视频"),
                    isUploading: isUploadingContextVideo,
                    errorMessage: cameraPanelErrorMessage,
                    onToggle: toggleCameraPanel,
                    onSelectVideo: presentVideoImporter
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

                                        HStack(spacing: 12) {
                                            metricCard(title: "等你次数", value: "\(anxietyReport.waitingCount) 次")
                                            metricCard(title: "累计等候", value: "\(anxietyReport.totalWaitingMinutes) 分钟")
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
                HStack {
                    Button {
                        isFeatureMenuPresented = true
                    } label: {
                        Label("更多能力", systemImage: "sparkles")
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

                    Spacer(minLength: 0)
                }
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
        .fileImporter(
            isPresented: $isVideoImporterPresented,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            Task {
                await importCameraVideo(from: result)
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
        .confirmationDialog("更多能力", isPresented: $isFeatureMenuPresented, titleVisibility: .visible) {
            Button("健康告警") {
                Task { await fetchHealthAlerts() }
            }
            Button("每日简报") {
                Task { await fetchDailyReport() }
            }
            Button("焦虑指数") {
                Task { await fetchAnxiety() }
            }
            Button("宠物日记") {
                Task { await fetchDiary() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Computed properties

    private var petAvatar: PetPalArtAsset {
        .pet(for: appStore.session.petSpecies)
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

        return "展开后可从文件中选择一段视频。"
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
                        relatedEventCard(event)
                            .padding(.leading, 42)
                    }
                }
            }
        }
    }

    private func textMessageBubble(_ message: ChatMessage) -> some View {
        Text(message.content)
            .font(.system(size: 14, weight: .medium, design: .rounded))
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

            Text(message.content)
                .font(.system(size: 14, weight: .medium, design: .rounded))
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

    private func relatedEventCard(_ event: RelatedEvent) -> some View {
        HStack(spacing: 10) {
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
                    .lineLimit(1)

                Text(formatEventTime(event.timestamp))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "F5EDE3").opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "E8D5C1").opacity(0.5), lineWidth: 1)
        )
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

    private func presentVideoImporter() {
        guard !isUploadingContextVideo else { return }
        cameraPanelErrorMessage = nil
        isVideoImporterPresented = true
    }

    private func importCameraVideo(from result: Result<[URL], Error>) async {
        cameraPanelErrorMessage = nil

        let urls: [URL]
        do {
            urls = try result.get()
        } catch {
            cameraPanelErrorMessage = "无法读取你选择的视频，请重新试一次。"
            return
        }

        guard let sourceURL = urls.first else { return }

        do {
            let copiedURL = try copyImportedVideo(from: sourceURL)
            let pickedVideo = PickedVideo(url: copiedURL)
            await uploadContextVideo(pickedVideo)
        } catch {
            cameraPanelErrorMessage = "导入视频失败：\(error.localizedDescription)"
        }
    }

    private func copyImportedVideo(from sourceURL: URL) throws -> URL {
        let startedAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = sourceURL.pathExtension.ifEmpty("mov")
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
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
        healthAlerts = []
        anxietyReport = nil
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
        healthAlerts = []
        anxietyReport = nil
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
        await fetchTextAction(
            prompt: "给我看看你今天的简报吧",
            request: { try await appStore.apiClient.fetchDailyReport(petID: petID).report }
        )
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
        healthAlerts = []
        anxietyReport = nil
        messages.append(ChatMessage(role: .user, content: prompt))

        do {
            let content = try await request()
            messages.append(ChatMessage(role: .assistant, content: content))
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }
}

private struct CameraContextPanel: View {
    @Binding var isExpanded: Bool
    let previewURL: URL?
    let cameraName: String
    let statusText: String
    let detailText: String
    let videoName: String
    let isUploading: Bool
    let errorMessage: String?
    let onToggle: () -> Void
    let onSelectVideo: () -> Void

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
                    Button(action: onSelectVideo) {
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
                    .accessibilityHint("从文件管理器选择一段视频来更新聊天上下文")

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
                VideoPlayer(player: AVPlayer(url: previewURL))
                    .allowsHitTesting(false)
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

                Text("从文件里选择一段视频作为今天的上下文。")
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
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .background(Color.black.opacity(0.08))
            .onDisappear {
                player.pause()
                player.seek(to: .zero)
            }
    }
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
