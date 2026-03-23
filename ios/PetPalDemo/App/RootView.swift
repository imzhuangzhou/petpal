import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        NavigationStack {
            Group {
                switch appStore.onboardingRoute {
                case .petSetup(let step):
                    PetSetupView(initialStep: step)
                case .cameraSetup:
                    DemoVideoUploadView()
                case .derivedFromSession:
                    if appStore.session.userId == nil {
                        WelcomeView()
                    } else if appStore.session.petId == nil {
                        PetSetupView()
                    } else if !appStore.session.setupComplete {
                        DemoVideoUploadView()
                    } else {
                        ChatView()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

enum PetPalTheme {
    static let cream0 = Color(hex: "FFFDF8")
    static let cream1 = Color(hex: "FFF8EE")
    static let cream2 = Color(hex: "F8EFE2")
    static let peach1 = Color(hex: "FFD6BF")
    static let peach2 = Color(hex: "F6B992")
    static let sage = Color(hex: "CFE4CC")
    static let mint = Color(hex: "DFF2E5")
    static let caramel = Color(hex: "A96B4B")
    static let cocoa = Color(hex: "694D3F")
    static let ink = Color(hex: "4D3A31")
    static let inkSoft = Color(hex: "7C675D")
    static let line = Color(hex: "EBDCC8")
    static let lineStrong = Color(hex: "DDC7AF")
    static let success = Color(hex: "71A06F")
    static let warning = Color(hex: "D3973B")
    static let danger = Color(hex: "CF6A5A")

    // Additional UI colors (consolidated from hardcoded values)
    static let alertCriticalBg = Color(hex: "FFE5E0")
    static let alertWarningBg = Color(hex: "FFF4D5")
    static let alertSuccessBg = Color(hex: "E4F4E8")
    static let anxietyRelaxed = Color(hex: "527053")
    static let anxietyMild = Color(hex: "7C5A27")
    static let selectionActive = Color(hex: "EDA579")
    static let surfaceCream = Color(hex: "FFF8EF")
    static let surfaceWarm = Color(hex: "FFF7EF")
    static let avatarSurfaceTop = Color(hex: "FFFBF6")
    static let avatarSurfaceBottom = Color(hex: "FFF4E9")
    static let avatarSurfaceSelectedTop = Color(hex: "FFF8EF")
    static let avatarSurfaceSelectedBottom = Color(hex: "FEEEDC")
    static let avatarSurfaceStroke = Color(hex: "E9DDCE")
    static let avatarSurfaceSelectedStroke = Color(hex: "E7A37B")
    static let avatarHalo = Color(hex: "FFF0DD")

    static let pageGradient = LinearGradient(
        colors: [Color(hex: "FFFAF2"), Color(hex: "FFF7F0"), Color(hex: "F8F2E8")],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardFill = Color.white.opacity(0.94)
    static let cardStrongFill = Color(hex: "FFFAF3")
    static let chatUserGradient = LinearGradient(
        colors: [Color(hex: "F4A774"), Color(hex: "F08E74")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let inkGradient = LinearGradient(
        colors: [Color(hex: "795548"), Color(hex: "5C4033")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let mintGradient = LinearGradient(
        colors: [Color(hex: "EAF6E8"), Color(hex: "D8ECDC")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct PetPalShell<Content: View>: View {
    private let alignment: Alignment
    private let content: Content

    init(alignment: Alignment = .top, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: alignment) {
            PetPalBackground()
                .ignoresSafeArea()

            content
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
    }
}

struct PetPalBackground: View {
    var body: some View {
        ZStack {
            PetPalTheme.pageGradient

            RadialGradient(
                colors: [PetPalTheme.peach1.opacity(0.48), .clear],
                center: UnitPoint(x: 0.12, y: 0.08),
                startRadius: 20,
                endRadius: 220
            )

            RadialGradient(
                colors: [PetPalTheme.mint.opacity(0.42), .clear],
                center: UnitPoint(x: 0.88, y: 0.1),
                startRadius: 24,
                endRadius: 210
            )

            Rectangle()
                .fill(PetPalTheme.cream0.opacity(0.9))
                .overlay(
                    ZStack {
                        RadialGradient(
                            colors: [PetPalTheme.peach1.opacity(0.5), .clear],
                            center: UnitPoint(x: 0.12, y: 0.12),
                            startRadius: 10,
                            endRadius: 90
                        )

                        RadialGradient(
                            colors: [PetPalTheme.mint.opacity(0.45), .clear],
                            center: UnitPoint(x: 0.88, y: 0.14),
                            startRadius: 10,
                            endRadius: 100
                        )
                    }
                )
                .padding(.horizontal, 6)
                .shadow(color: PetPalTheme.caramel.opacity(0.18), radius: 34, y: 12)
        }
    }
}

struct PetPalHeroCard: View {
    let badge: String
    let stampAsset: PetPalArtAsset
    let stampImageURL: URL?
    let title: String
    let subtitle: String

    init(
        badge: String,
        stampAsset: PetPalArtAsset,
        stampImageURL: URL? = nil,
        title: String,
        subtitle: String
    ) {
        self.badge = badge
        self.stampAsset = stampAsset
        self.stampImageURL = stampImageURL
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(PetPalTheme.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(PetPalTheme.line.opacity(0.84), lineWidth: 1)
                )
                .shadow(color: PetPalTheme.caramel.opacity(0.12), radius: 18, y: 8)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "FFF0DA").opacity(0.72))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(12))
                .padding(20)

            VStack(alignment: .leading, spacing: 16) {
                PetPalCapsuleLabel(text: badge, style: .hero)

                HStack(alignment: .center, spacing: 16) {
                    PetPalStamp(fallbackAsset: stampAsset, imageURL: stampImageURL)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(PetPalTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(PetPalTheme.inkSoft)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(22)
        }
    }
}

struct PetPalPanelCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(PetPalTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.78), lineWidth: 1)
        )
        .shadow(color: PetPalTheme.caramel.opacity(0.1), radius: 14, y: 8)
    }
}

struct PetPalSurfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "FFF8EE").opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.8), lineWidth: 1)
        )
    }
}

struct PetPalSectionHeader: View {
    let eyebrow: String
    let title: String
    let chipText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.caramel)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let chipText {
                PetPalCapsuleLabel(text: chipText, style: .sticker)
            }
        }
    }
}

struct PetPalCapsuleLabel: View {
    enum Style {
        case hero
        case sticker
        case soft
        case context
        case videoTag
    }

    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .black, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(background)
            .overlay(border)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        switch style {
        case .soft:
            return Color(hex: "608261")
        case .hero, .sticker, .context, .videoTag:
            return PetPalTheme.caramel
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .soft:
            Color(hex: "E3F0E5").opacity(0.95)
        case .hero:
            Color(hex: "FFE3C9").opacity(0.85)
        case .context, .videoTag:
            Color(hex: "FFF0DC").opacity(0.95)
        case .sticker:
            Color(hex: "FFEDD7").opacity(0.96)
        }
    }

    @ViewBuilder
    private var border: some View {
        switch style {
        case .sticker:
            Capsule()
                .stroke(PetPalTheme.caramel.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        default:
            EmptyView()
        }
    }
}

struct PetPalStamp: View {
    let fallbackAsset: PetPalArtAsset
    let imageURL: URL?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "FFF6E5"), .clear],
                        center: .topLeading,
                        startRadius: 6,
                        endRadius: 36
                    )
                )

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFD9B3"), Color(hex: "FFBF93")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: 70, height: 70)
        .overlay(
            PetPalImageFill(
                imageURL: imageURL,
                fallbackAsset: fallbackAsset,
                artSize: 34,
                contentMode: .fill
            )
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .padding(8)
        )
        .rotationEffect(.degrees(-5))
        .shadow(color: Color(hex: "EFB082").opacity(0.28), radius: 16, y: 10)
    }
}

struct PetPalImageFill: View {
    let imageURL: URL?
    let fallbackAsset: PetPalArtAsset
    let artSize: CGFloat
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .empty:
                        fallbackContent
                    case .failure:
                        fallbackContent
                    @unknown default:
                        fallbackContent
                    }
                }
            } else {
                fallbackContent
            }
        }
    }

    private var fallbackContent: some View {
        ZStack {
            LinearGradient(
                colors: fallbackAsset.placeholderColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: artSize * 1.25, height: artSize * 1.25)
                .offset(x: artSize * 0.3, y: -artSize * 0.35)

            PetPalArtImage(asset: fallbackAsset)
                .frame(width: artSize, height: artSize)
                .shadow(color: .white.opacity(0.18), radius: 6, y: 1)
        }
    }
}

struct PetPalAvatarSurface<Content: View>: View {
    let isSelected: Bool
    let cornerRadius: CGFloat
    private let content: Content

    init(
        isSelected: Bool = false,
        cornerRadius: CGFloat = 22,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? [PetPalTheme.avatarSurfaceSelectedTop, PetPalTheme.avatarSurfaceSelectedBottom]
                            : [PetPalTheme.avatarSurfaceTop, PetPalTheme.avatarSurfaceBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RadialGradient(
                        colors: [PetPalTheme.avatarHalo.opacity(isSelected ? 0.58 : 0.34), .clear],
                        center: UnitPoint(x: 0.5, y: 0.34),
                        startRadius: 8,
                        endRadius: 150
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )

            content
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isSelected
                        ? PetPalTheme.avatarSurfaceSelectedStroke.opacity(0.68)
                        : PetPalTheme.avatarSurfaceStroke.opacity(0.58),
                    lineWidth: isSelected ? 1.25 : 0.9
                )
        )
    }
}

struct PetPalStepIndicator: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(width: index == current ? 28 : 10, height: 10)
            }
        }
        .padding(.top, 16)
    }

    private func fill(for index: Int) -> LinearGradient {
        if index < current {
            return LinearGradient(
                colors: [Color(hex: "C7DFC3"), Color(hex: "C7DFC3")],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        if index == current {
            return LinearGradient(
                colors: [Color(hex: "F2AF81"), Color(hex: "EB8E76")],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [PetPalTheme.lineStrong.opacity(0.85), PetPalTheme.lineStrong.opacity(0.85)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct PetPalInfoRow: View {
    let title: String
    let value: String
    var valueColor: Color = PetPalTheme.ink

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct PetPalLoadingOverlay: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        ZStack {
            Color.white.opacity(0.82)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(hex: "EF986A"))

                Text(title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(hex: "FFF8EF").opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(PetPalTheme.line.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: PetPalTheme.caramel.opacity(0.12), radius: 20, y: 10)
            .padding(.horizontal, 24)
        }
    }
}

struct PetPalChatHeader: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let avatar: PetPalArtAsset
    let avatarImageURL: URL?
    let title: String
    let statusLines: [String]
    let subtitle: String
    let trailing: AnyView?

    @State private var statusRotationStartDate = Date()
    private let statusRotationInterval: TimeInterval = 2.8

    init<Trailing: View>(
        avatar: PetPalArtAsset,
        avatarImageURL: URL? = nil,
        title: String,
        statusLines: [String] = [],
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.avatar = avatar
        self.avatarImageURL = avatarImageURL
        self.title = title
        self.statusLines = statusLines
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    init(
        avatar: PetPalArtAsset,
        avatarImageURL: URL? = nil,
        title: String,
        statusLines: [String] = [],
        subtitle: String
    ) {
        self.avatar = avatar
        self.avatarImageURL = avatarImageURL
        self.title = title
        self.statusLines = statusLines
        self.subtitle = subtitle
        self.trailing = nil
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFD8B4"), Color(hex: "F8B78D")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
                .overlay(
                    PetPalImageFill(
                        imageURL: avatarImageURL,
                        fallbackAsset: avatar,
                        artSize: 24,
                        contentMode: .fill
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(4)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)

                if !statusLines.isEmpty {
                    statusCarouselLine
                }

                Text(subtitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.success)
            }

            Spacer(minLength: 10)

            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .safeAreaPadding(.top, 8)
        .background(Color(hex: "FFFBF5").opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "E6D5C2").opacity(0.76))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var statusCarouselLine: some View {
        if statusLines.count == 1, let line = statusLines.first {
            statusText(line)
        } else if accessibilityReduceMotion {
            TimelineView(.periodic(from: statusRotationStartDate, by: statusRotationInterval)) { context in
                statusText(statusLines[currentStatusIndex(for: context.date)])
            }
        } else {
            TimelineView(.periodic(from: statusRotationStartDate, by: 0.14)) { context in
                let index = currentStatusIndex(for: context.date)
                let emphasis = currentStatusEmphasis(for: context.date)

                statusText(statusLines[index], emphasis: emphasis)
            }
        }
    }

    private func statusText(_ text: String, emphasis: Double = 1) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(PetPalTheme.inkSoft)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            .opacity(0.82 + (0.18 * emphasis))
            .scaleEffect(0.992 + (0.008 * emphasis), anchor: .leading)
            .offset(y: (1 - emphasis) * 1.5)
            .accessibilityLabel("宠物状态 \(text)")
    }

    private func currentStatusIndex(for date: Date) -> Int {
        guard !statusLines.isEmpty else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(statusRotationStartDate))
        let step = Int(elapsed / statusRotationInterval)
        return step % statusLines.count
    }

    private func currentStatusEmphasis(for date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(statusRotationStartDate))
        let cycleProgress = elapsed.truncatingRemainder(dividingBy: statusRotationInterval)
        let ramp = min(cycleProgress / 0.42, 1)
        return 1 - pow(1 - ramp, 3)
    }
}

struct PetPalNavigationHeader: View {
    let title: String
    var backTitle: String = "返回"
    var onBack: (() -> Void)? = nil
    let trailing: AnyView?

    init<Trailing: View>(
        title: String,
        backTitle: String = "返回",
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.backTitle = backTitle
        self.onBack = onBack
        self.trailing = AnyView(trailing())
    }

    init(
        title: String,
        backTitle: String = "返回",
        onBack: (() -> Void)? = nil
    ) {
        self.title = title
        self.backTitle = backTitle
        self.onBack = onBack
        self.trailing = nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let onBack {
                    Button(action: onBack) {
                        Label(backTitle, systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PetPalSmallGhostButtonStyle())
                    .accessibilityLabel(backTitle)
                } else {
                    Color.clear
                        .frame(width: 84, height: 42)
                }
            }
            .frame(width: 84, alignment: .leading)

            Spacer(minLength: 0)

            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            Group {
                if let trailing {
                    trailing
                } else {
                    Color.clear
                        .frame(width: 84, height: 42)
                }
            }
            .frame(width: 84, alignment: .trailing)
        }
        .padding(.top, 16)
        .safeAreaPadding(.top, 8)
    }
}

struct PetPalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(PetPalTheme.chatUserGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color(hex: "ED936F").opacity(0.35), radius: 14, y: 8)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

enum PetPalFeedbackTone {
    case neutral
    case success
    case warning
    case danger

    var iconName: String {
        switch self {
        case .neutral:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .danger:
            return "xmark.circle.fill"
        }
    }

    var foreground: Color {
        switch self {
        case .neutral:
            return PetPalTheme.ink
        case .success:
            return PetPalTheme.success
        case .warning:
            return PetPalTheme.warning
        case .danger:
            return PetPalTheme.danger
        }
    }

    var background: Color {
        switch self {
        case .neutral:
            return Color(hex: "FFF6EA")
        case .success:
            return Color(hex: "EEF7ED")
        case .warning:
            return Color(hex: "FFF4E2")
        case .danger:
            return Color(hex: "FDEEEB")
        }
    }

    var border: Color {
        switch self {
        case .neutral:
            return PetPalTheme.line
        case .success:
            return PetPalTheme.success.opacity(0.32)
        case .warning:
            return PetPalTheme.warning.opacity(0.34)
        case .danger:
            return PetPalTheme.danger.opacity(0.34)
        }
    }
}

struct PetPalInlineFeedback: View {
    let message: String
    var tone: PetPalFeedbackTone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tone.foreground)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tone.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tone.border, lineWidth: 1.2)
        )
        .accessibilityElement(children: .combine)
    }
}

func petPalBundledDemoVideoURL(named fileName: String) -> URL? {
    let trimmedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return nil }

    let lastPathComponent = URL(fileURLWithPath: trimmedName).lastPathComponent
    let resourceName = (lastPathComponent as NSString).deletingPathExtension
    let fileExtension = (lastPathComponent as NSString).pathExtension.isEmpty
        ? "mp4"
        : (lastPathComponent as NSString).pathExtension

    return Bundle.main.url(forResource: resourceName, withExtension: fileExtension)
        ?? Bundle.main.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "DemoVideos")
}

enum PetPalPlayableVideoControlsStyle: String {
    case system
    case minimal
}

struct PetPalPlayableVideoView: View {
    let url: URL
    var controlsStyle: PetPalPlayableVideoControlsStyle = .system

    var body: some View {
        PetPalPlayableVideoContent(url: url, controlsStyle: controlsStyle)
            .id("\(url.absoluteString)-\(controlsStyle.rawValue)")
    }
}

private struct PetPalPlayableVideoContent: View {
    @StateObject private var controller: PetPalPlayableVideoController

    private let controlsStyle: PetPalPlayableVideoControlsStyle

    init(url: URL, controlsStyle: PetPalPlayableVideoControlsStyle) {
        _controller = StateObject(wrappedValue: PetPalPlayableVideoController(url: url))
        self.controlsStyle = controlsStyle
    }

    var body: some View {
        ZStack {
            playerSurface
                .background(Color.black)

            playbackOverlay
        }
        .contentShape(Rectangle())
        .onDisappear {
            controller.stopPlayback()
        }
    }

    @ViewBuilder
    private var playerSurface: some View {
        switch controlsStyle {
        case .system:
            PetPalSystemVideoPlayer(player: controller.player)
        case .minimal:
            PetPalMinimalVideoPlayer(player: controller.player)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var playbackOverlay: some View {
        switch controlsStyle {
        case .system:
            if !controller.isPlaying {
                Button {
                    controller.startPlayback()
                } label: {
                    ZStack {
                        LinearGradient(
                            colors: [Color.black.opacity(0.08), Color.black.opacity(0.2), Color.black.opacity(0.36)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.92))
                                    .frame(width: 64, height: 64)

                                Image(systemName: "play.fill")
                                    .font(.system(size: 24, weight: .black))
                                    .foregroundStyle(PetPalTheme.caramel)
                                    .offset(x: 2)
                            }

                            Text("点击播放")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.26))
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        case .minimal:
            Button {
                controller.togglePlayback()
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: controller.isPlaying ? 18 : 24, weight: .black))
                    .foregroundStyle(controller.isPlaying ? .white : PetPalTheme.caramel)
                    .frame(
                        width: controller.isPlaying ? 46 : 66,
                        height: controller.isPlaying ? 46 : 66
                    )
                    .background(
                        controller.isPlaying
                            ? Color.black.opacity(0.34)
                            : Color.white.opacity(0.94)
                    )
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(controller.isPlaying ? 0.22 : 0.12), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .padding(controller.isPlaying ? 18 : 0)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: controller.isPlaying ? .bottomTrailing : .center
            )
            .background {
                if !controller.isPlaying {
                    LinearGradient(
                        colors: [Color.black.opacity(0.04), Color.black.opacity(0.16), Color.black.opacity(0.28)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
    }
}

@MainActor
final class PetPalPlayableVideoController: ObservableObject {
    let url: URL
    let player: AVPlayer

    @Published var isPlaying = false

    private var playbackEndedObserver: NSObjectProtocol?

    init(url: URL) {
        self.url = url
        self.player = AVPlayer(url: url)
        self.playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackEnded()
            }
        }
    }

    deinit {
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
        }
    }

    func startPlayback() {
        isPlaying = true
        player.seek(to: .zero)
        player.play()
    }

    func pausePlayback() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        isPlaying ? pausePlayback() : startPlayback()
    }

    func stopPlayback() {
        player.pause()
        player.seek(to: .zero)
        isPlaying = false
    }

    private func handlePlaybackEnded() {
        player.seek(to: .zero)
        isPlaying = false
    }
}

private struct PetPalSystemVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

private struct PetPalMinimalVideoPlayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PetPalVideoPlayerLayerView {
        let view = PetPalVideoPlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PetPalVideoPlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class PetPalVideoPlayerLayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

struct PetPalFieldLabel: View {
    let title: String
    var required: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)

            if required {
                Text("必填")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.caramel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(hex: "FFF1DF"))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color(hex: "F1D2B4"), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(required ? "\(title)，必填" : title)
    }
}

struct PetPalSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(PetPalTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(Color(hex: "FFF9F2").opacity(0.98))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PetPalTheme.line, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct PetPalSmallGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(PetPalTheme.ink)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color(hex: "FFF4E5").opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct PetPalIconGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(PetPalTheme.ink)
            .frame(width: 36, height: 36)
            .background(Color(hex: "FFF4E5").opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PetPalTheme.line.opacity(0.9), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct PetPalTextFieldModifier: ViewModifier {
    var isInvalid = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(PetPalTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isInvalid ? Color(hex: "FFF4F0") : PetPalTheme.cardStrongFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isInvalid ? PetPalTheme.danger : PetPalTheme.line, lineWidth: 1.5)
            )
    }
}

extension View {
    func petPalTextFieldStyle(isInvalid: Bool = false) -> some View {
        modifier(PetPalTextFieldModifier(isInvalid: isInvalid))
    }
}

enum PetPalHaptics {
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
