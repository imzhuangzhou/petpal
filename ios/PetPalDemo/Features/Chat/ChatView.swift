import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject private var appStore: AppStore
    @StateObject private var speechRecognizer = SpeechRecognizer()
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

    var body: some View {
        PetPalShell {
            VStack(spacing: 0) {
                PetPalChatHeader(
                    avatar: petAvatar,
                    avatarImageURL: petAvatarImageURL,
                    title: appStore.session.petName.ifEmpty("PetPal"),
                    subtitle: "今日上下文已加载，可以开始聊天了"
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
                    voiceLabel: voiceSettingName,
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
                                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                                    HStack(alignment: .top, spacing: 8) {
                                        if message.role == .assistant {
                                            chatAvatar
                                        }

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
                                            .clipShape(
                                                RoundedRectangle(
                                                    cornerRadius: 20,
                                                    style: .continuous
                                                )
                                            )
                                            .frame(maxWidth: 320, alignment: message.role == .user ? .trailing : .leading)

                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

                                    if message.role == .assistant && !message.relatedEvents.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Label("相关事件", systemImage: "paperclip")
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
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
                        .padding(.bottom, 150)
                    }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        featureButton(title: "健康告警", asset: .featureHealth) {
                            Task { await fetchHealthAlerts() }
                        }
                        featureButton(title: "每日简报", asset: .featureReport) {
                            Task { await fetchDailyReport() }
                        }
                        featureButton(title: "焦虑指数", asset: .featureAnxiety) {
                            Task { await fetchAnxiety() }
                        }
                        featureButton(title: "宠物日记", asset: .featureDiary) {
                            Task { await fetchDiary() }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .background(Color(hex: "FFFBF4").opacity(0.94))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: "E6D5C2").opacity(0.76))
                        .frame(height: 1)
                }

                HStack(spacing: 10) {
                    Button {
                        if speechRecognizer.isListening {
                            speechRecognizer.stopListening()
                            draft = speechRecognizer.transcript
                        } else {
                            speechRecognizer.requestAuthorization()
                            speechRecognizer.startListening()
                        }
                    } label: {
                        Image(systemName: speechRecognizer.isListening ? "waveform.circle.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .black))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .background(
                        speechRecognizer.isListening
                            ? Color(hex: "FFE5E0").opacity(0.9)
                            : Color(hex: "FFF7EE").opacity(0.96)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                speechRecognizer.isListening
                                    ? Color(hex: "E58A7F").opacity(0.8)
                                    : PetPalTheme.line,
                                lineWidth: 1.5
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel(speechRecognizer.isListening ? "停止录音" : "开始语音输入")

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
                            await sendMessage()
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .black))
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(ChatSendButtonStyle())
                    .disabled(!canSendMessage)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .background(Color(hex: "FFFBF5").opacity(0.96))
            }
        }
        .task {
            if messages.isEmpty {
                messages = [
                    ChatMessage(
                        role: .assistant,
                        content: openingLine(
                            style: appStore.session.languageStyle,
                            species: appStore.session.petSpecies
                        )
                    )
                ]
            }
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
        .onChange(of: speechRecognizer.transcript) {
            if speechRecognizer.isListening {
                draft = speechRecognizer.transcript
            }
        }
        .onDisappear {
            cleanupSelectedPreviewVideo()
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

    private var voiceSettingName: String {
        appStore.session.voiceLabel.ifEmpty("默认萌宠声线")
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
            return "正在上传并解析新视频..."
        }

        if let cameraPanelErrorMessage {
            return cameraPanelErrorMessage
        }

        return latestCameraSummary
            ?? (hasCameraContextVideo
                ? "\(cameraContextName) 已接入，轻点展开查看或更新视频。"
                : "还没有视频上下文，上传后聊天会结合真实画面来回答。")
    }

    private var cameraPanelDetailText: String {
        if isUploadingContextVideo {
            return "我们会抽帧分析视频内容，并把识别出的行为事件立即同步到当前对话。"
        }

        if hasCameraContextVideo {
            return "当前摄像头：\(cameraContextName) · 声音设定：\(voiceSettingName)"
        }

        return "展开后点击 4:3 区域，从文件管理器选择一段视频来生成今天的陪伴上下文。"
    }

    private var canSendMessage: Bool {
        !isSubmitting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                Text(event.description)
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

    private func featureButton(title: String, asset: PetPalArtAsset, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                PetPalArtImage(asset: asset)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
            }
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

    private func alertBackground(_ level: String) -> Color {
        switch level {
        case "critical":
            return Color(hex: "FFE5E0").opacity(0.86)
        case "warning":
            return Color(hex: "FFF4D5").opacity(0.85)
        default:
            return Color(hex: "E4F4E8").opacity(0.8)
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
            return Color(hex: "527053")
        case "mild":
            return Color(hex: "7C5A27")
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

    private func openingLine(style: String, species: String) -> String {
        if style == "loyal" {
            return species == "dog"
                ? "主人！我今天一直守着门口，终于等到你来找我啦！"
                : "主人主人，我今天也有乖乖等你，快夸夸我。"
        }

        if style == "chatty" {
            return species == "dog"
                ? "你知道吗你知道吗，今天家里发生了好多事，我都记住了！"
                : "你终于来了，我今天从窗边看到好多小动静，想讲给你听。"
        }

        if style == "chill" {
            return "今天还算不错，阳光、零食和想你这件事都刚刚好。"
        }

        return species == "dog"
            ? "哼，我才不是特地在等你，只是刚好想和你说说今天的事。"
            : "哼，你终于想起来看我了？我今天在门口等了你好一会儿。"
    }

    // MARK: - Actions

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

    private func sendMessage() async {
        guard let petID = appStore.session.petId else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        draft = ""
        errorMessage = nil
        isSubmitting = true
        healthAlerts = []
        anxietyReport = nil
        messages.append(ChatMessage(role: .user, content: trimmed))

        // Create an empty assistant message for streaming
        let streamMessageID = UUID()
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
        anxietyReport = nil
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
        healthAlerts = []
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
    let voiceLabel: String
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

                            HStack(spacing: 8) {
                                PetPalCapsuleLabel(text: cameraName, style: .context)
                                PetPalCapsuleLabel(text: voiceLabel, style: .soft)
                            }
                            .padding(16)

                            if isUploading {
                                VStack(spacing: 10) {
                                    ProgressView()
                                        .controlSize(.large)
                                        .tint(.white)

                                    Text("正在解析上传视频")
                                        .font(.system(size: 14, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("抽帧识别完成后会立即更新聊天上下文")
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
                        .shadow(color: Color(hex: "D39A74").opacity(0.12), radius: 18, y: 10)
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
        .shadow(color: Color(red: 173 / 255, green: 131 / 255, blue: 98 / 255).opacity(0.1), radius: 14, y: 8)
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

                Text("支持从文件管理器选择视频，上传后会自动解析真实行为事件。")
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
