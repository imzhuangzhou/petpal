import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    private let onboardingSteps = ["添加爱宠", "连接摄像头", "开始聊天"]

    var body: some View {
        PetPalShell(alignment: .center) {
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 0) {
                    welcomeMark
                        .padding(.bottom, 10)

                    Text("PetPal")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)

                    Text("每一帧，都是它想对你说的话")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .padding(.top, 8)
                        .padding(.bottom, 22)

                    stepsSection
                        .padding(.bottom, 18)

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
                                Text("开始创建宠物")
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

                Spacer(minLength: 24)
            }
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
        HStack(spacing: 10) {
            ForEach(Array(onboardingSteps.enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(PetPalTheme.inkSoft.opacity(0.7))
                }

                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.8), lineWidth: 1)
        )
        .frame(maxWidth: 360)
    }

    private func onboardingErrorMessage(for error: Error) -> String {
        let backendCommand = "cd /Users/justin/Documents/demo/petpal/backend && ./start.sh"
        let healthCheckCommand = "curl http://127.0.0.1:8000/"

        if let apiError = error as? APIError {
            switch apiError {
            case .noConnection, .timedOut:
                return """
                无法连接本地服务，请先启动后端后再试。
                \(backendCommand)
                启动后可执行：
                \(healthCheckCommand)
                """
            case .requestFailed:
                return """
                首屏请求没有连上本地服务（\(AppEnvironment.apiBaseURLString)）。
                请先启动后端：
                \(backendCommand)
                启动后可执行：
                \(healthCheckCommand)
                """
            default:
                return apiError.errorDescription ?? error.localizedDescription
            }
        }

        return error.localizedDescription
    }
}
