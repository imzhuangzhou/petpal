import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .title2) private var heroTopSpacing = 30.0
    @ScaledMetric(relativeTo: .body) private var contentSpacing = 26.0
    @ScaledMetric(relativeTo: .body) private var contentHorizontalPadding = 20.0

    private let onboardingSteps = [
        WelcomeStep(
            index: "01",
            symbolName: "heart.text.square.fill",
            title: "添加爱宠",
            subtitle: "创建它的专属档案"
        ),
        WelcomeStep(
            index: "02",
            symbolName: "video.fill",
            title: "连接摄像头",
            subtitle: "开始识别它的日常状态"
        ),
        WelcomeStep(
            index: "03",
            symbolName: "message.fill",
            title: "开始聊天",
            subtitle: "收到更像它亲口说的话"
        ),
    ]

    var body: some View {
        PetPalShell {
            GeometryReader { geometry in
                let contentWidth = min(max(geometry.size.width - 40, 280), 520)
                let isCompactHeight = geometry.size.height < 760

                ScrollView(showsIndicators: false) {
                    VStack(spacing: contentSpacing) {
                        Spacer(minLength: isCompactHeight ? 8 : 18)

                        WelcomeHero(compactLayout: isCompactHeight)

                        WelcomeStepsSection(
                            steps: onboardingSteps,
                            useVerticalLayout: contentWidth < 390
                        )

                        Spacer(minLength: isCompactHeight ? 8 : 20)
                    }
                    .frame(maxWidth: contentWidth)
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.top, heroTopSpacing)
                    .padding(.bottom, isCompactHeight ? 120 : 136)
                    .frame(maxWidth: .infinity)
                    .frame(
                        minHeight: max(geometry.size.height - (isCompactHeight ? 96 : 112), 0),
                        alignment: .top
                    )
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WelcomeBottomCTA(
                isSubmitting: isSubmitting,
                errorMessage: errorMessage
            ) {
                Task {
                    await startOnboarding()
                }
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

private struct WelcomeHero: View {
    let compactLayout: Bool

    @ScaledMetric(relativeTo: .title) private var markSize = 110.0
    @ScaledMetric(relativeTo: .largeTitle) private var glowSize = 188.0
    @ScaledMetric(relativeTo: .title2) private var pawSize = 46.0

    var body: some View {
        VStack(spacing: compactLayout ? 18 : 22) {
            PetPalCapsuleLabel(text: "与爱宠开始第一段对话", style: .soft)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "FFE8D7").opacity(0.9),
                                Color(hex: "FFF8EF").opacity(0.0),
                            ],
                            center: .center,
                            startRadius: 12,
                            endRadius: glowSize / 2
                        )
                    )
                    .frame(width: glowSize, height: glowSize)
                    .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.46))
                    .frame(width: markSize + 16, height: markSize + 16)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -10, y: 6)
                    .shadow(color: PetPalTheme.caramel.opacity(0.06), radius: 22, y: 10)
                    .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FFF7ED"), Color(hex: "FFEAD8")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: markSize, height: markSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(Color.white.opacity(0.72), lineWidth: 1)
                    )
                    .shadow(color: Color(hex: "EFB082").opacity(0.18), radius: 24, y: 12)

                Image(systemName: "pawprint.fill")
                    .font(.system(size: pawSize, weight: .black))
                    .foregroundStyle(PetPalTheme.inkGradient)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, compactLayout ? 2 : 8)

            VStack(spacing: compactLayout ? 8 : 12) {
                Text("PetPal")
                    .font(.system(size: compactLayout ? 42 : 46, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .multilineTextAlignment(.center)

                Text("每一帧，都是它想对你说的话。\n用更自然的方式记录、理解，再开始聊天。")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WelcomeStepsSection: View {
    let steps: [WelcomeStep]
    let useVerticalLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("三步开始")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.caramel)
                    .textCase(.uppercase)
                    .tracking(1.1)

                Text("几分钟完成初始设置，很快就能收到它专属的回应。")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                if useVerticalLayout {
                    VStack(spacing: 12) {
                        ForEach(steps) { step in
                            WelcomeStepCard(step: step)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(steps) { step in
                            WelcomeStepCard(step: step)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: PetPalTheme.caramel.opacity(0.08), radius: 20, y: 10)
    }
}

private struct WelcomeStepCard: View {
    let step: WelcomeStep

    @ScaledMetric(relativeTo: .body) private var symbolBadgeSize = 34.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(step.index)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.caramel)
                    .frame(minWidth: 32, minHeight: 28)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule()
                            .fill(Color(hex: "FFF0DE"))
                    )

                Spacer(minLength: 0)

                Image(systemName: step.symbolName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PetPalTheme.caramel)
                    .frame(width: symbolBadgeSize, height: symbolBadgeSize)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.78))
                    )
                    .overlay(
                        Circle()
                            .stroke(PetPalTheme.line.opacity(0.65), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "FFF9F1").opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.75), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomeBottomCTA: View {
    let isSubmitting: Bool
    let errorMessage: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("约 30 秒完成初始设置")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)
                .multilineTextAlignment(.center)

            if let errorMessage {
                PetPalInlineFeedback(message: errorMessage, tone: .danger)
            }

            Button(action: action) {
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
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [
                        PetPalTheme.cream0.opacity(0.0),
                        PetPalTheme.cream0.opacity(0.92),
                        PetPalTheme.cream0,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Rectangle()
                    .fill(PetPalTheme.line.opacity(0.45))
                    .frame(height: 1)
            }
        )
    }
}

private struct WelcomeStep: Identifiable {
    let index: String
    let symbolName: String
    let title: String
    let subtitle: String

    var id: String { index }
}
