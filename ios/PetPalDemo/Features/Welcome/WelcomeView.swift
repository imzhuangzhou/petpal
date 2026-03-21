import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isFloating = false
    private let onboardingSteps: [OnboardingStep] = [
        .init(
            number: "1",
            symbolName: "pawprint.fill",
            title: "添加爱宠",
            subtitle: "设定宠物名字、品种和专属性格。"
        ),
        .init(
            number: "2",
            symbolName: "video.fill",
            title: "添加摄像头",
            subtitle: "搜索并绑定家庭摄像头，接入今天的实时画面。"
        ),
        .init(
            number: "3",
            symbolName: "message.fill",
            title: "与爱宠聊天",
            subtitle: "用它自己的口吻，告诉你今天发生了什么。"
        ),
    ]

    var body: some View {
        PetPalShell(alignment: .center) {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                VStack(spacing: 0) {
                    welcomeMark
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

                    stepsSection
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
                            .multilineTextAlignment(.center)
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

    // MARK: - Pieces

    private var welcomeMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFF6EC"), Color(hex: "FFE8D0")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 116, height: 116)
                .shadow(color: Color(hex: "EFB082").opacity(0.2), radius: 18, y: 10)

            Image(systemName: "pawprint.fill")
                .font(.system(size: 54, weight: .black))
                .foregroundStyle(PetPalTheme.inkGradient)
        }
    }

    // MARK: - Action

    private func startOnboarding() async {
        guard !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let response = try await appStore.apiClient.createUser(nickname: "宠物主人")
            appStore.applyCreatedUser(response)
        } catch {
            errorMessage = onboardingErrorMessage(for: error)
        }
    }

    private var stepsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(onboardingSteps) { step in
                    stepCard(step)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: 360)
        .scrollClipDisabled()
    }

    private func stepCard(_ step: OnboardingStep) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                stepBadge(step.number)

                Spacer(minLength: 10)

                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: "FFF3E4"))
                        .frame(width: 46, height: 46)

                    Image(systemName: step.symbolName)
                        .font(.system(size: 19, weight: .black))
                        .foregroundStyle(PetPalTheme.ink)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)

                Text(step.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .lineSpacing(2)
                    .lineLimit(3)
            }
        }
        .frame(width: 196, alignment: .topLeading)
        .frame(minHeight: 152, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.8), lineWidth: 1)
        )
    }

    private func stepBadge(_ number: String) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color(hex: "FFD8B5"), Color(hex: "F6BE95")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 34, height: 34)
            .overlay(
                Text(number)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            )
    }

    private func onboardingErrorMessage(for error: Error) -> String {
        let backendCommand = "cd /Users/justin/Documents/demo/petpal/backend && uvicorn main:app --reload --host 0.0.0.0 --port 8000"

        if let apiError = error as? APIError {
            switch apiError {
            case .noConnection, .timedOut:
                return """
                无法连接本地服务，请先启动后端后再试。
                \(backendCommand)
                """
            case .requestFailed:
                return """
                首屏请求没有连上本地服务（\(AppEnvironment.apiBaseURLString)）。
                请先启动后端：
                \(backendCommand)
                """
            default:
                return apiError.errorDescription ?? error.localizedDescription
            }
        }

        return error.localizedDescription
    }
}

private struct OnboardingStep: Identifiable {
    let number: String
    let symbolName: String
    let title: String
    let subtitle: String

    var id: String { number }
}
