import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var appStore: AppStore
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var draft = ""
    @State private var messages: [ChatMessage] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var healthAlerts: [HealthAlert] = []
    @State private var anxietyReport: AnxietyResponse?

    var body: some View {
        PetPalShell {
            VStack(spacing: 0) {
                PetPalChatHeader(
                    avatar: petAvatar,
                    title: appStore.session.petName.ifEmpty("PetPal"),
                    subtitle: "今日上下文已加载，可以开始聊天了"
                ) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Text("⚙️")
                    }
                    .buttonStyle(PetPalSmallGhostButtonStyle())
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PetPalCapsuleLabel(
                            text: "视频上下文：\(appStore.session.demoVideoName.ifEmpty("已接入演示视频"))",
                            style: .context
                        )
                        PetPalCapsuleLabel(
                            text: "声音设定：\(appStore.session.voiceLabel.ifEmpty("默认萌宠声线"))",
                            style: .context
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            PetPalSurfaceCard {
                                Text("今天的陪伴模式已经准备好")
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                    .foregroundStyle(PetPalTheme.ink)

                                Text("现在的对话会结合 \(appStore.session.demoVideoName.ifEmpty("当前视频")) 生成的行为事件来回答你。")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(PetPalTheme.inkSoft)
                                    .lineSpacing(3)
                            }

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

                                        if message.role == .user {
                                            Spacer(minLength: 0)
                                        } else {
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

                                    // Related events cards
                                    if message.role == .assistant && !message.relatedEvents.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("📎 相关事件")
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
                                    Text("🩺 身体状况报告")
                                        .font(.system(size: 15, weight: .black, design: .rounded))
                                        .foregroundStyle(PetPalTheme.ink)

                                    VStack(spacing: 8) {
                                        ForEach(healthAlerts, id: \.self) { alert in
                                            HStack(alignment: .top, spacing: 10) {
                                                Text(alert.level == "critical" ? "🚨" : alert.level == "warning" ? "⚠️" : "✅")
                                                    .font(.system(size: 20))

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
                                    Text("😟 分离焦虑指数")
                                        .font(.system(size: 15, weight: .black, design: .rounded))
                                        .foregroundStyle(PetPalTheme.ink)

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
                        featureButton("🩺 健康告警") {
                            Task { await fetchHealthAlerts() }
                        }
                        featureButton("📋 每日简报") {
                            Task { await fetchDailyReport() }
                        }
                        featureButton("😟 焦虑指数") {
                            Task { await fetchAnxiety() }
                        }
                        featureButton("📖 宠物日记") {
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
                    // Microphone button
                    Button {
                        if speechRecognizer.isListening {
                            speechRecognizer.stopListening()
                            draft = speechRecognizer.transcript
                        } else {
                            speechRecognizer.requestAuthorization()
                            speechRecognizer.startListening()
                        }
                    } label: {
                        Text(speechRecognizer.isListening ? "🔴" : "🎤")
                            .font(.system(size: 18))
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
                        Text("⬆️")
                            .font(.system(size: 18))
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
        .onChange(of: speechRecognizer.transcript) {
            if speechRecognizer.isListening {
                draft = speechRecognizer.transcript
            }
        }
    }

    // MARK: - Computed properties

    private var petAvatar: String {
        appStore.session.petSpecies == "dog" ? "🐶" : "🐱"
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
                Text(petAvatar)
                    .font(.system(size: 18))
            )
            .padding(.top, 4)
    }

    // MARK: - Related event card

    private func relatedEventCard(_ event: RelatedEvent) -> some View {
        HStack(spacing: 10) {
            Text(eventIcon(event.eventType))
                .font(.system(size: 16))

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

    private func eventIcon(_ type: String) -> String {
        switch type {
        case "eating": return "🍽️"
        case "drinking": return "💧"
        case "sleeping": return "😴"
        case "playing": return "🎾"
        case "resting": return "☀️"
        case "waiting": return "🚪"
        case "litter_box": return "🧹"
        case "zoomies": return "⚡"
        default: return "📌"
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

    private func featureButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
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
