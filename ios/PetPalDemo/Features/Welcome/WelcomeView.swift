import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var nickname = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isFloating = false

    var body: some View {
        PetPalShell(alignment: .center) {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                VStack(spacing: 0) {
                    Text("🐾")
                        .font(.system(size: 78))
                        .offset(y: isFloating ? -10 : 0)
                        .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: isFloating)
                        .padding(.bottom, 12)

                    PetPalCapsuleLabel(text: "Warm companion OS", style: .hero)
                        .padding(.bottom, 12)

                    Text("PetPal")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)

                    Text("每一帧，都是它想对你说的话")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .padding(.top, 10)
                        .padding(.bottom, 28)

                    VStack(spacing: 14) {
                        TextField("怎么称呼你？(你的昵称)", text: $nickname)
                            .textInputAutocapitalization(.never)
                            .petPalTextFieldStyle()
                            .accessibilityLabel("昵称输入框")

                        Button {
                            Task {
                                await createUser()
                            }
                        } label: {
                            Group {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("开始我们的故事")
                                }
                            }
                        }
                        .buttonStyle(PetPalPrimaryButtonStyle())
                        .disabled(isSubmitting || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityHint("创建主人资料并进入宠物创建页")

                    }
                    .frame(maxWidth: 360)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(PetPalTheme.danger)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)
            }
        }
        .onAppear {
            isFloating = true
        }
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
