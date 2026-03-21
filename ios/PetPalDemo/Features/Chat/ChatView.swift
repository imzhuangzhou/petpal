import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var draft = ""
    @State private var messages: [ChatMessage] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var healthAlerts: [HealthAlert] = []
    @State private var anxietyReport: AnxietyResponse?

    var body: some View {
        List {
            Section("宠物信息") {
                LabeledContent("昵称", value: appStore.session.nickname)
                LabeledContent("宠物", value: appStore.session.petName)
                LabeledContent("种类", value: appStore.session.petSpecies)
                LabeledContent("视频", value: appStore.session.demoVideoName)
            }

            Section("消息") {
                ForEach(messages, id: \.self) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.role == .user ? "你" : appStore.session.petName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(message.content)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if !healthAlerts.isEmpty {
                Section("健康告警") {
                    ForEach(healthAlerts, id: \.self) { alert in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.title)
                                .font(.headline)
                            Text(alert.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("级别：\(alert.level)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if let anxietyReport {
                Section("焦虑指数") {
                    LabeledContent("分数", value: "\(anxietyReport.score)")
                    LabeledContent("级别", value: anxietyReport.level)
                    LabeledContent("说明", value: anxietyReport.comment)
                    LabeledContent("等候次数", value: "\(anxietyReport.waitingCount)")
                    LabeledContent("累计等候分钟", value: "\(anxietyReport.totalWaitingMinutes)")
                }
            }

            Section("快捷功能") {
                Button("每日简报") {
                    Task {
                        await fetchDailyReport()
                    }
                }
                .disabled(isSubmitting)

                Button("健康告警") {
                    Task {
                        await fetchHealthAlerts()
                    }
                }
                .disabled(isSubmitting)

                Button("焦虑指数") {
                    Task {
                        await fetchAnxiety()
                    }
                }
                .disabled(isSubmitting)

                Button("宠物日记") {
                    Task {
                        await fetchDiary()
                    }
                }
                .disabled(isSubmitting)
            }

            Section("输入") {
                TextField("和宠物聊聊天...", text: $draft)
                    .accessibilityLabel("聊天输入框")

                Button {
                    Task {
                        await sendMessage()
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("发送")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSubmitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("配置") {
                LabeledContent("API Base URL", value: appStore.apiClient.baseURL.absoluteString)

                NavigationLink("设置") {
                    SettingsView()
                }
            }
        }
        .navigationTitle("Chat")
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

        return species == "dog"
            ? "哼，我才不是特地在等你，只是刚好想和你说说今天的事。"
            : "哼，你终于想起来看我了？我今天在门口等了你好一会儿。"
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

        do {
            let response = try await appStore.apiClient.sendChat(petID: petID, message: trimmed)
            messages.append(ChatMessage(role: .assistant, content: response.reply))
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
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
