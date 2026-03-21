import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appStore: AppStore
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
                        .padding(.bottom, 32)

                    // 3-step guide
                    VStack(spacing: 0) {
                        stepRow(
                            number: "1",
                            icon: "🐱",
                            title: "添加爱宠",
                            subtitle: "设定宠物名字、品种和专属性格",
                            isLast: false
                        )
                        stepRow(
                            number: "2",
                            icon: "📹",
                            title: "添加摄像头",
                            subtitle: "上传家庭摄像头视频，建立行为档案",
                            isLast: false
                        )
                        stepRow(
                            number: "3",
                            icon: "💬",
                            title: "与爱宠聊天",
                            subtitle: "它会用自己的口吻告诉你今天发生了什么",
                            isLast: true
                        )
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.88))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(PetPalTheme.line.opacity(0.7), lineWidth: 1)
                    )
                    .frame(maxWidth: 360)
                    .padding(.bottom, 24)

                    Button {
                        Task {
                            await startOnboarding()
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
                    .disabled(isSubmitting)
                    .accessibilityHint("进入宠物创建页")
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

    // MARK: - Step row

    private func stepRow(
        number: String,
        icon: String,
        title: String,
        subtitle: String,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Left: number badge + connector line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FFD8B5"), Color(hex: "F6BE95")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Text(number)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }

                if !isLast {
                    Rectangle()
                        .fill(PetPalTheme.line)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)

            // Right: icon + text
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 26))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .lineSpacing(2)
                }
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
    }

    // MARK: - Action

    private func startOnboarding() async {
        isSubmitting = true
        errorMessage = nil

        do {
            let response = try await appStore.apiClient.createUser(nickname: "宠物主人")
            appStore.applyCreatedUser(response)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }
}
