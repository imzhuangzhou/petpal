import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        NavigationStack {
            Group {
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

            content
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
        .ignoresSafeArea()
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
                .shadow(color: Color(red: 147 / 255, green: 106 / 255, blue: 77 / 255).opacity(0.18), radius: 34, y: 12)
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
                .shadow(color: Color(red: 173 / 255, green: 131 / 255, blue: 98 / 255).opacity(0.12), radius: 18, y: 8)

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
        .shadow(color: Color(red: 173 / 255, green: 131 / 255, blue: 98 / 255).opacity(0.1), radius: 14, y: 8)
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct PetPalLoadingOverlay: View {
    let title: String
    let subtitle: String

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

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
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
            .shadow(color: Color(red: 161 / 255, green: 117 / 255, blue: 85 / 255).opacity(0.12), radius: 20, y: 10)
            .padding(.horizontal, 24)
        }
    }
}

struct PetPalChatHeader: View {
    let avatar: PetPalArtAsset
    let avatarImageURL: URL?
    let title: String
    let subtitle: String
    let trailing: AnyView?

    init<Trailing: View>(
        avatar: PetPalArtAsset,
        avatarImageURL: URL? = nil,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.avatar = avatar
        self.avatarImageURL = avatarImageURL
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    init(
        avatar: PetPalArtAsset,
        avatarImageURL: URL? = nil,
        title: String,
        subtitle: String
    ) {
        self.avatar = avatar
        self.avatarImageURL = avatarImageURL
        self.title = title
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
        .padding(.vertical, 16)
        .background(Color(hex: "FFFBF5").opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: "E6D5C2").opacity(0.76))
                .frame(height: 1)
        }
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

struct PetPalTextFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(PetPalTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PetPalTheme.cardStrongFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PetPalTheme.line, lineWidth: 1.5)
            )
    }
}

extension View {
    func petPalTextFieldStyle() -> some View {
        modifier(PetPalTextFieldModifier())
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
