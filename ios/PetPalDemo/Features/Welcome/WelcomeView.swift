import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var nickname = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("开始") {
                Text("先创建主人昵称，再继续进入宠物创建流程。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("你的昵称", text: $nickname)
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("昵称输入框")

                Button {
                    Task {
                        await createUser()
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("继续")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSubmitting || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("创建主人资料并进入宠物创建页")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("后端配置") {
                LabeledContent("API Base URL", value: appStore.apiClient.baseURL.absoluteString)
            }
        }
        .navigationTitle("Welcome")
    }

    private func createUser() async {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNickname.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        do {
            let response = try await appStore.apiClient.createUser(nickname: trimmedNickname)
            appStore.applyCreatedUser(response)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }
}
