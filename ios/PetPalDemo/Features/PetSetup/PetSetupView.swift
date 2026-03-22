import PhotosUI
import SwiftUI
import UIKit

struct PetSetupView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var currentStep = 0
    @State private var petName = ""
    @State private var ownerAlias = ""
    @State private var species = "cat"
    @State private var style = "tsundere"
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var selectedReferencePhotoItem: PhotosPickerItem?
    @State private var referencePhotoLocalURL: URL?
    @State private var referencePhotoRemotePath = ""
    @State private var generatedAvatarRemotePath = ""
    @State private var avatarGenerationState: AvatarGenerationState = .idle
    @State private var avatarMessage: String?
    private let referencePhotoMaxDimension: CGFloat = 1600
    private let referencePhotoCompressionQuality: CGFloat = 0.85

    private let speciesOptions = [
        SpeciesOption(id: "cat", artAsset: .petCat, label: "喵星人", summary: "轻盈、敏感、会把心事藏在尾巴尖。"),
        SpeciesOption(id: "dog", artAsset: .petDog, label: "汪星人", summary: "热情、黏人、会把开心都写在眼睛里。"),
    ]

    private let styleOptions = [
        StyleOption(id: "tsundere", artAsset: .styleTsundere, name: "傲娇主子", desc: "嘴上不说，心里却记得你什么时候回家。"),
        StyleOption(id: "loyal", artAsset: .styleLoyal, name: "忠诚小跟班", desc: "每一句回应都像摇着尾巴朝你跑来。"),
        StyleOption(id: "chatty", artAsset: .styleChatty, name: "碎碎念搭子", desc: "芝麻大的小事，也想马上讲给你听。"),
        StyleOption(id: "chill", artAsset: .styleChill, name: "松弛感主角", desc: "不慌不忙，连撒娇都带着午后阳光味。"),
    ]

    var body: some View {
        PetPalShell {
            GeometryReader { geometry in
                let contentWidth = min(max(geometry.size.width - 40, 280), 520)
                let isCompactLayout = contentWidth < 360
                let viewportHeight = geometry.size.height

                ZStack {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            PetPalStepIndicator(total: 2, current: currentStep)

                            if currentStep == 0 {
                                stepOneIdentityCard()
                            } else {
                                PetPalHeroCard(
                                    badge: "Pet setup",
                                    stampAsset: selectedSpecies.artAsset,
                                    stampImageURL: currentHeroImageURL,
                                    title: heroTitle,
                                    subtitle: heroSubtitle
                                )
                            }

                            PetPalPanelCard {
                                switch currentStep {
                                case 0:
                                    stepOneContent(
                                        contentWidth: contentWidth,
                                        isCompactLayout: isCompactLayout,
                                        viewportHeight: viewportHeight
                                    )
                                default:
                                    stepTwoContent(contentWidth: contentWidth, isCompactLayout: isCompactLayout)
                                }
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(PetPalTheme.danger)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .safeAreaPadding(.top, 12)
                    .scrollBounceBehavior(.basedOnSize)

                    if isSubmitting {
                        PetPalLoadingOverlay(
                            title: "正在建立宠物档案...",
                            subtitle: "我们会保存参考照片和聊天人格，接着进入演示视频上传。"
                        )
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .onChange(of: selectedReferencePhotoItem) {
            Task {
                await importReferencePhoto()
            }
        }
        .onDisappear {
            cleanupReferencePhotoFile()
        }
    }

    private var selectedSpecies: SpeciesOption {
        speciesOptions.first(where: { $0.id == species }) ?? speciesOptions[0]
    }

    private var trimmedPetName: String {
        petName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedOwnerAlias: String {
        ownerAlias.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var referencePhotoResolvedURL: URL? {
        appStore.apiClient.resolvedURL(for: referencePhotoRemotePath)
    }

    private var generatedAvatarResolvedURL: URL? {
        appStore.apiClient.resolvedURL(for: generatedAvatarRemotePath)
    }

    private var currentHeroImageURL: URL? {
        generatedAvatarResolvedURL ?? referencePhotoResolvedURL
    }

    private var heroTitle: String {
        switch currentStep {
        case 0:
            return "先认识一下新伙伴"
        default:
            return "给它一点说话脾气"
        }
    }

    private var heroSubtitle: String {
        switch currentStep {
        case 0:
            return "上传照片、补上名字与种类，就能完成建档。"
        default:
            return "选一种聊天语气，让它更像你熟悉的样子。"
        }
    }

    private var canContinueFromStepOne: Bool {
        !trimmedPetName.isEmpty &&
        !referencePhotoRemotePath.isEmpty &&
        !generatedAvatarRemotePath.isEmpty &&
        avatarGenerationState == .generated
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case 0:
            return "继续设置聊天人格"
        default:
            return "完成建档"
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        if isSubmitting {
            return true
        }

        if currentStep == 0 {
            return !canContinueFromStepOne
        }

        return false
    }

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if currentStep > 0 {
                    Button("上一步") {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(PetPalSecondaryButtonStyle())
                    .frame(width: 118)
                }

                Button {
                    handlePrimaryAction()
                } label: {
                    Text(primaryButtonTitle)
                }
                .buttonStyle(PetPalPrimaryButtonStyle())
                .disabled(isPrimaryButtonDisabled)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [
                    PetPalTheme.cream0.opacity(0),
                    PetPalTheme.cream0.opacity(0.96),
                    PetPalTheme.cream0
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private func stepOneIdentityCard() -> some View {
        PetPalPanelCard {
            Text("宠物信息")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)

            Text("先填写基础信息，再上传照片生成头像。")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)

            VStack(alignment: .leading, spacing: 8) {
                Text("名字")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)

                TextField("例如：发财、奶盖、奥利奥...", text: $petName)
                    .petPalTextFieldStyle()
                    .accessibilityLabel("宠物名字输入框")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("它怎么称呼你")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)

                TextField("例如：boss、妈妈、小陈...", text: $ownerAlias)
                    .petPalTextFieldStyle()
                    .accessibilityLabel("宠物主人称呼输入框")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("宠物种类")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)

                HStack(spacing: 12) {
                    ForEach(speciesOptions) { option in
                        Button {
                            species = option.id
                        } label: {
                            compactSpeciesTile(option: option, isSelected: species == option.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stepOneContent(
        contentWidth _: CGFloat,
        isCompactLayout: Bool,
        viewportHeight: CGFloat
    ) -> some View {
        stepOneArtworkCard(isCompactLayout: isCompactLayout, viewportHeight: viewportHeight)
    }

    @ViewBuilder
    private func stepTwoContent(contentWidth: CGFloat, isCompactLayout: Bool) -> some View {
        PetSetupStepHeader(
            eyebrow: "聊天人格",
            title: "它平时会怎么跟你说话？",
            chipText: "Step 2",
            onSkip: {
                Task {
                    await skipStyleStep()
                }
            }
        )

        LazyVGrid(columns: optionColumns(for: contentWidth), spacing: 12) {
            ForEach(styleOptions) { option in
                Button {
                    style = option.id
                } label: {
                    optionTile(
                        artAsset: option.artAsset,
                        title: option.name,
                        subtitle: option.desc,
                        isSelected: style == option.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func stepOneArtworkCard(isCompactLayout: Bool, viewportHeight: CGFloat) -> some View {
        let previewHeight = artworkPreviewHeight(isCompactLayout: isCompactLayout, viewportHeight: viewportHeight)

        PetPalSurfaceCard {
            Text("上传 1 张清晰照片，系统会生成头像。")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)

            switch avatarGenerationState {
            case .idle:
                PhotosPicker(
                    selection: $selectedReferencePhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    PetSetupAvatarPlaceholder(
                        title: "上传宠物照片",
                        subtitle: "选择 1 张五官或特征清晰的照片。",
                        height: previewHeight,
                        accentAsset: selectedSpecies.artAsset
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开系统照片选择器选择宠物参考照片")
            case .generating:
                PetSetupAvatarLoadingCard(height: previewHeight)
            case .generated:
                PetSetupArtworkPreview(
                    remoteImageURL: generatedAvatarResolvedURL,
                    fallbackAsset: selectedSpecies.artAsset,
                    height: previewHeight
                )
            case .failed:
                PetSetupAvatarPlaceholder(
                    title: "这次没有成功生成卡通形象",
                    subtitle: avatarMessage?.ifEmpty("你可以重试生成，也可以直接更换另一张参考照片。") ?? "你可以重试生成，也可以直接更换另一张参考照片。",
                    height: previewHeight,
                    accentAsset: .avatarPalette
                )
            }

            if avatarGenerationState != .generating,
               let avatarMessage,
               !avatarMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                Text(avatarMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(avatarGenerationState == .failed ? PetPalTheme.warning : PetPalTheme.inkSoft)
                    .lineSpacing(3)
            }

            switch avatarGenerationState {
            case .generated:
                HStack(spacing: 10) {
                    Button("重新生成") {
                        Task {
                            await retryAvatarGeneration()
                        }
                    }
                    .buttonStyle(PetPalSecondaryButtonStyle())

                    PhotosPicker(
                        selection: $selectedReferencePhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Text("更换照片")
                    }
                    .buttonStyle(PetPalSecondaryButtonStyle())
                }
            case .failed:
                if isCompactLayout {
                    VStack(spacing: 10) {
                        Button("重试生成") {
                            Task {
                                await retryAvatarGeneration()
                            }
                        }
                        .buttonStyle(PetPalSecondaryButtonStyle())

                        PhotosPicker(
                            selection: $selectedReferencePhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Text("更换照片")
                        }
                        .buttonStyle(PetPalSecondaryButtonStyle())
                    }
                } else {
                    HStack(spacing: 10) {
                        Button("重试生成") {
                            Task {
                                await retryAvatarGeneration()
                            }
                        }
                        .buttonStyle(PetPalSecondaryButtonStyle())

                        PhotosPicker(
                            selection: $selectedReferencePhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Text("更换照片")
                        }
                        .buttonStyle(PetPalSecondaryButtonStyle())
                    }
                }
            default:
                EmptyView()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(avatarBorderColor, lineWidth: 1.2)
        )
    }

    private func artworkPreviewHeight(isCompactLayout: Bool, viewportHeight: CGFloat) -> CGFloat {
        let minimumHeight = isCompactLayout ? 144.0 : 156.0
        let preferredHeight = isCompactLayout ? 156.0 : 176.0
        let scaledHeight = viewportHeight * (isCompactLayout ? 0.2 : 0.225)
        return max(minimumHeight, min(preferredHeight, scaledHeight))
    }

    private func optionColumns(for contentWidth: CGFloat) -> [GridItem] {
        if contentWidth < 360 {
            return [GridItem(.flexible(), spacing: 12)]
        }

        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }

    @ViewBuilder
    private func compactSpeciesTile(option: SpeciesOption, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            PetPalArtImage(asset: option.artAsset)
                .frame(width: 26, height: 26)

            Text(option.label)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 58)
        .padding(.horizontal, 14)
        .background(tileFill(isSelected: isSelected))
        .overlay(tileBorder(isSelected: isSelected))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func optionTile(
        artAsset: PetPalArtAsset,
        title: String,
        subtitle: String,
        isSelected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PetPalArtImage(asset: artAsset)
                .frame(width: 34, height: 34)

            Text(title)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tileFill(isSelected: isSelected))
        .overlay(tileBorder(isSelected: isSelected))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func tileFill(isSelected: Bool) -> some View {
        if isSelected {
            LinearGradient(
                colors: [Color(hex: "FFF8EF"), Color(hex: "FFF2E3")],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color(hex: "FFF9F1").opacity(0.95)
        }
    }

    private func tileBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(
                isSelected ? Color(hex: "EDA579") : PetPalTheme.line,
                lineWidth: 1.5
            )
    }

    private var avatarBorderColor: Color {
        switch avatarGenerationState {
        case .failed:
            return Color(hex: "E4C18A")
        case .generated:
            return Color(hex: "EDA579")
        case .generating:
            return Color(hex: "E7C8B2")
        case .idle:
            return PetPalTheme.line.opacity(0.8)
        }
    }

    private func handlePrimaryAction() {
        errorMessage = nil

        switch currentStep {
        case 0:
            advanceFromStepOne()
        default:
            Task {
                await createPet()
            }
        }
    }

    private func skipStyleStep() async {
        style = "tsundere"
        await createPet()
    }

    private func advanceFromStepOne() {
        errorMessage = nil

        if trimmedPetName.isEmpty {
            errorMessage = "请先填写宠物名字。"
            return
        }

        if referencePhotoRemotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "请先上传目标宠物参考照片。"
            return
        }

        if avatarGenerationState != .generated || generatedAvatarRemotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "请先生成卡通形象。"
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            currentStep = 1
        }
    }

    private func retryAvatarGeneration() async {
        guard let referencePhotoLocalURL else {
            avatarGenerationState = .failed
            avatarMessage = "找不到本地参考照片，请重新上传。"
            return
        }

        await generateAvatar(from: referencePhotoLocalURL)
    }

    private func importReferencePhoto() async {
        errorMessage = nil

        guard let selectedReferencePhotoItem else {
            return
        }
        defer { self.selectedReferencePhotoItem = nil }

        do {
            guard let photoData = try await selectedReferencePhotoItem.loadTransferable(type: Data.self) else {
                errorMessage = "无法读取你选择的图片，请重新试一次。"
                return
            }

            let copiedURL = try persistSelectedReferencePhoto(data: photoData)
            cleanupReferencePhotoFile()
            referencePhotoLocalURL = copiedURL
            referencePhotoRemotePath = ""
            generatedAvatarRemotePath = ""
            avatarGenerationState = .generating
            avatarMessage = "照片已上传，正在生成头像..."
            await generateAvatar(from: copiedURL)
        } catch {
            errorMessage = "导入参考照片失败：\(error.localizedDescription)"
        }
    }

    private func generateAvatar(from localURL: URL) async {
        avatarGenerationState = .generating
        avatarMessage = "正在生成头像..."

        do {
            let response = try await appStore.apiClient.generatePetAvatar(
                species: species,
                imageFileURL: localURL
            )
            referencePhotoRemotePath = response.photoURL
            generatedAvatarRemotePath = response.avatarURL

            if response.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                avatarGenerationState = .failed
                avatarMessage = response.generationError?.ifEmpty("卡通形象暂时生成失败，但参考照片已经保存。") ?? "卡通形象暂时生成失败，但参考照片已经保存。"
            } else {
                avatarGenerationState = .generated
                avatarMessage = "头像已生成，可以继续下一步。"
            }
        } catch {
            avatarGenerationState = .failed
            avatarMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func persistSelectedReferencePhoto(data: Data) throws -> URL {
        guard let image = UIImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let preparedImage = resizedReferencePhotoIfNeeded(image)

        guard let normalizedData = preparedImage.jpegData(compressionQuality: referencePhotoCompressionQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try normalizedData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private func resizedReferencePhotoIfNeeded(_ image: UIImage) -> UIImage {
        let originalSize = image.size
        let maxSide = max(originalSize.width, originalSize.height)

        guard maxSide > referencePhotoMaxDimension else {
            return image
        }

        let scale = referencePhotoMaxDimension / maxSide
        let resizedSize = CGSize(
            width: max(originalSize.width * scale, 1),
            height: max(originalSize.height * scale, 1)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: resizedSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: resizedSize))
        }
    }

    private func cleanupReferencePhotoFile() {
        guard let referencePhotoLocalURL else { return }
        try? FileManager.default.removeItem(at: referencePhotoLocalURL)
        self.referencePhotoLocalURL = nil
    }

    private func createPet() async {
        guard let userID = appStore.session.userId else { return }

        if trimmedPetName.isEmpty {
            errorMessage = "请先填写宠物名字。"
            currentStep = 0
            return
        }

        if referencePhotoRemotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "请先上传目标宠物参考照片。"
            currentStep = 0
            return
        }

        if avatarGenerationState != .generated || generatedAvatarRemotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "请先生成卡通形象。"
            currentStep = 0
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            let request = CreatePetRequest(
                userID: userID,
                name: trimmedPetName,
                species: species,
                photoURL: referencePhotoRemotePath,
                avatarURL: generatedAvatarRemotePath,
                languageStyle: style,
                ownerAlias: trimmedOwnerAlias
            )

            let response = try await appStore.apiClient.createPet(request)

            appStore.applyCreatedPet(
                response: response,
                name: trimmedPetName,
                species: species,
                style: style,
                ownerAlias: trimmedOwnerAlias
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }
}

private struct PetSetupStepHeader: View {
    let eyebrow: String
    let title: String
    let chipText: String
    var onSkip: (() -> Void)? = nil

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

            VStack(alignment: .trailing, spacing: 8) {
                PetPalCapsuleLabel(text: chipText, style: .sticker)

                if let onSkip {
                    Button("跳过") {
                        onSkip()
                    }
                    .buttonStyle(PetPalSmallGhostButtonStyle())
                }
            }
        }
    }
}

private struct PetSetupImageCard: View {
    let title: String
    let subtitle: String
    let badgeText: String
    let localImageURL: URL?
    let remoteImageURL: URL?
    let fallbackAsset: PetPalArtAsset
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .lineSpacing(3)
                }

                Spacer(minLength: 8)

                PetPalCapsuleLabel(text: badgeText, style: .hero)
            }

            content
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(PetPalTheme.line.opacity(0.8), lineWidth: 1)
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "FFF8EE").opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PetPalTheme.line.opacity(0.75), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        if let localImageURL, let image = UIImage(contentsOfFile: localImageURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let remoteImageURL {
            AsyncImage(url: remoteImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    placeholder
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "FFF4E5"), Color(hex: "FFE8D6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                PetPalArtImage(asset: fallbackAsset)
                    .frame(width: 48, height: 48)

                Text("等待图片")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
            }
        }
    }
}

private struct PetSetupAvatarPlaceholder: View {
    let title: String
    let subtitle: String
    let height: CGFloat
    let accentAsset: PetPalArtAsset

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "FFF4E9"), Color(hex: "FFE9D8")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: height)
            .overlay {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 72, height: 72)

                        PetPalArtImage(asset: accentAsset)
                            .frame(width: 40, height: 40)
                    }

                    VStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(PetPalTheme.ink)
                            .multilineTextAlignment(.center)

                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PetPalTheme.inkSoft)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 24)
                    }
                }
            }
    }
}

private struct PetSetupArtworkPreview: View {
    let remoteImageURL: URL?
    let fallbackAsset: PetPalArtAsset
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "FFF6EC"), Color(hex: "FFEBDD")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if let remoteImageURL {
            AsyncImage(url: remoteImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                case .empty, .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "FFF3E5"), Color(hex: "FFE2CC")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                PetPalArtImage(asset: fallbackAsset)
                    .frame(width: 48, height: 48)

                Text("等待图片")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
            }
        }
    }
}

private struct PetSetupAvatarLoadingCard: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "FFF4EA"), Color(hex: "FFEBDD")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: height)
            .overlay {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 72, height: 72)

                        ProgressView()
                            .controlSize(.large)
                            .tint(Color(hex: "EF986A"))
                    }

                    VStack(spacing: 8) {
                        Text("正在生成头像")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(PetPalTheme.ink)

                        Text("请稍等片刻，完成后可以更换照片或继续下一步。")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PetPalTheme.inkSoft)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 24)
                    }
                }
            }
    }
}

private enum AvatarGenerationState: Equatable {
    case idle
    case generating
    case generated
    case failed
}

private struct SpeciesOption: Identifiable {
    let id: String
    let artAsset: PetPalArtAsset
    let label: String
    let summary: String
}

private struct StyleOption: Identifiable {
    let id: String
    let artAsset: PetPalArtAsset
    let name: String
    let desc: String
}
