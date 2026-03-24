import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .title3) private var topPadding = 24.0
    @ScaledMetric(relativeTo: .body) private var horizontalPadding = 20.0

    private let onboardingSteps = [
        WelcomeStep(
            index: "1",
            symbolName: "heart.text.square.fill",
            title: "添加爱宠",
            subtitle: "创建它的专属档案"
        ),
        WelcomeStep(
            index: "2",
            symbolName: "video.fill",
            title: "连接摄像头",
            subtitle: "开始识别它的日常状态"
        ),
        WelcomeStep(
            index: "3",
            symbolName: "message.fill",
            title: "开始聊天",
            subtitle: "收到更像它亲口说的话"
        ),
    ]

    var body: some View {
        PetPalShell {
            GeometryReader { geometry in
                let contentWidth = min(max(geometry.size.width - 40, 280), 420)
                let isCompactHeight = geometry.size.height < 760
                let verticalSpacing = isCompactHeight ? 14.0 : 18.0

                ScrollView(showsIndicators: false) {
                    VStack(spacing: verticalSpacing) {
                        Spacer(minLength: isCompactHeight ? 8 : 14)

                        WelcomeCompactHero(compactLayout: isCompactHeight)

                        WelcomeCompactStepsSection(steps: onboardingSteps)

                        if let errorMessage {
                            PetPalInlineFeedback(message: errorMessage, tone: .danger)
                        }

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

                        Spacer(minLength: isCompactHeight ? 10 : 16)
                    }
                    .frame(maxWidth: contentWidth)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, topPadding)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

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

    private func onboardingErrorMessage(for error: Error) -> String {
        let backendCommand = "cd /Users/justin/Documents/demo/petpal/backend && ./start.sh"
        let healthCheckCommand = "curl \(AppEnvironment.apiBaseURLString)/"

        if let apiError = error as? APIError {
            switch apiError {
            case .noConnection, .timedOut:
                return """
                无法连接本地服务，请先确认 iPhone 已开启个人热点、Mac 已连上热点，再启动后端后重试。
                \(backendCommand)
                启动后可执行：
                \(healthCheckCommand)
                """
            case .requestFailed:
                return """
                首屏请求没有连上本地服务（\(AppEnvironment.apiBaseURLString)）。
                请先确认 iPhone 已开启个人热点、Mac 已连上热点，再启动后端：
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

private struct WelcomeCompactHero: View {
    let compactLayout: Bool

    @ScaledMetric(relativeTo: .title3) private var iconSize = 74.0
    @ScaledMetric(relativeTo: .title) private var glowSize = 132.0

    var body: some View {
        VStack(spacing: compactLayout ? 10 : 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "FFE5D0").opacity(0.78),
                                Color(hex: "FFF8EF").opacity(0),
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: glowSize / 2
                        )
                    )
                    .frame(width: glowSize, height: glowSize)
                    .accessibilityHidden(true)

                Image("WelcomeAppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: PetPalTheme.caramel.opacity(0.14), radius: 18, y: 10)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, compactLayout ? 2 : 4)

            Text("PetPal")
                .font(.system(size: compactLayout ? 38 : 40, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)
                .multilineTextAlignment(.center)

            Text("每一帧，都是它想对你说的话")
                .font(.system(size: compactLayout ? 15 : 16, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomeCompactStepsSection: View {
    let steps: [WelcomeStep]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                WelcomeStepRow(step: step)

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(PetPalTheme.line.opacity(0.85))
                        .frame(height: 1)
                        .padding(.leading, 58)
                        .padding(.trailing, 14)
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: PetPalTheme.caramel.opacity(0.08), radius: 18, y: 10)
    }
}

private struct WelcomeStepRow: View {
    let step: WelcomeStep

    @ScaledMetric(relativeTo: .body) private var badgeSize = 30.0

    var body: some View {
        HStack(spacing: 12) {
            Text(step.index)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.caramel)
                .frame(width: badgeSize, height: badgeSize)
                .background(
                    Circle()
                        .fill(Color(hex: "FFF0DE"))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)

                Text(step.subtitle)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)
            }

            Spacer(minLength: 8)

            Image(systemName: step.symbolName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PetPalTheme.caramel)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomeStep: Identifiable {
    let index: String
    let symbolName: String
    let title: String
    let subtitle: String

    var id: String { index }
}
