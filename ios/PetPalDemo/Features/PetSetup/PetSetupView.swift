import PhotosUI
import SwiftUI
import UIKit

struct PetSetupView: View {
    @EnvironmentObject private var appStore: AppStore
    @FocusState private var focusedField: StepOneFocusableField?
    @AccessibilityFocusState private var accessibilityFocusedField: StepOneFocusableField?
    @State private var currentStep: Int
    @State private var petName = ""
    @State private var ownerAlias = ""
    @State private var species = "cat"
    @State private var style = "tsundere"
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var selectedReferencePhotoItem: PhotosPickerItem?
    @State private var isShowingReferencePhotoPicker = false
    @State private var referencePhotoLocalURL: URL?
    @State private var referencePhotoRemotePath = ""
    @State private var generatedAvatarRemotePath = ""
    @State private var avatarGenerationJobID = ""
    @State private var avatarGenerationState: AvatarGenerationState = .idle
    @State private var avatarInputMode: AvatarInputMode = .photoGenerated
    @State private var selectedCatDefaultAvatarID = "cat_american_shorthair"
    @State private var selectedDogDefaultAvatarID = "dog_beagle"
    @State private var avatarMessage: String?
    @State private var avatarPollingTask: Task<Void, Never>?
    @State private var hasAttemptedStepOneSubmit = false
    @State private var hasScrolledToBottom = false
    @State private var scrollPosition: String?
    @State private var hasRestoredDraft = false
    private let initialStep: Int
    private let referencePhotoMaxDimension: CGFloat = 1280
    private let referencePhotoCompressionQuality: CGFloat = 0.75
    private let avatarPollingIntervalNanoseconds: UInt64 = 1_500_000_000
    private let avatarPollingMaxFailures = 3

    private let speciesOptions = petPalSpeciesOptions
    private let styleOptions = petPalStyleOptions
    private let defaultAvatarOptions = petPalDefaultAvatarOptions

    init(initialStep: Int = 0) {
        let clampedStep = min(max(initialStep, 0), 1)
        self.initialStep = clampedStep
        _currentStep = State(initialValue: clampedStep)
    }

    var body: some View {
        PetPalShell {
            ScrollViewReader { scrollProxy in
                GeometryReader { geometry in
                    let contentWidth = min(max(geometry.size.width - 40, 280), 520)
                    let isCompactLayout = contentWidth < 360
                    let viewportHeight = geometry.size.height

                    ZStack {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                PetPalStepIndicator(total: 3, current: currentStep)

                                if currentStep == 0 {
                                    stepOneIdentityCard()
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
                                        stepTwoContent(
                                            contentWidth: contentWidth,
                                            isCompactLayout: isCompactLayout,
                                            scrollProxy: scrollProxy
                                        )
                                    }
                                }

                                if let errorMessage {
                                    PetPalInlineFeedback(message: errorMessage, tone: .danger)
                                }

                                if !hasScrolledToBottom {
                                    bottomActionBar(scrollProxy: scrollProxy)
                                        .padding(.top, 8)
                                }

                                bottomAnchor
                                    .id("bottomAnchor")
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                        }
                        .safeAreaPadding(.top, 12)
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollPosition(id: $scrollPosition)
                        .onChange(of: scrollPosition) { _, newValue in
                            if newValue == "bottomAnchor" {
                                hasScrolledToBottom = true
                            }
                        }

                        if isSubmitting {
                            PetPalLoadingOverlay(
                                title: "正在建立宠物档案...",
                                subtitle: "我们会保存参考照片和聊天人格，接着进入演示视频上传。"
                            )
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if hasScrolledToBottom {
                        bottomActionBar(scrollProxy: scrollProxy)
                    } else {
                        Color.clear
                            .frame(height: 1)
                    }
                }
            }
        }
        .onChange(of: selectedReferencePhotoItem) {
            Task {
                await importReferencePhoto()
            }
        }
        .photosPicker(
            isPresented: $isShowingReferencePhotoPicker,
            selection: $selectedReferencePhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onAppear {
            restoreDraftIfNeeded()
            resumeAvatarGenerationPollingIfNeeded()
        }
        .onChange(of: currentPetSetupDraft) { _, newDraft in
            appStore.applyPetSetupDraft(newDraft)
        }
        .onDisappear {
            cancelAvatarGenerationPolling()
            syncPetSetupDraft()
            cleanupReferencePhotoFile()
        }
    }

    private var bottomAnchor: some View {
        Color.clear
            .frame(height: 1)
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
        guard !isUsingDefaultAvatar else { return nil }
        return generatedAvatarResolvedURL ?? referencePhotoResolvedURL
    }

    private var currentHeroArtAsset: PetPalArtAsset {
        isUsingDefaultAvatar ? selectedDefaultAvatarOption.artAsset : selectedSpecies.artAsset
    }

    private var isUsingDefaultAvatar: Bool {
        avatarInputMode == .defaultArt
    }

    private var selectedDefaultAvatarID: String {
        species == "dog" ? selectedDogDefaultAvatarID : selectedCatDefaultAvatarID
    }

    private var visibleDefaultAvatarOptions: [DefaultAvatarOption] {
        defaultAvatarOptions.filter { $0.species == species }
    }

    private var selectedDefaultAvatarOption: DefaultAvatarOption {
        visibleDefaultAvatarOptions.first(where: { $0.id == selectedDefaultAvatarID }) ?? visibleDefaultAvatarOptions[0]
    }

    private var currentPetSetupDraft: PetSetupDraft {
        PetSetupDraft(
            petName: petName,
            ownerAlias: ownerAlias,
            species: species,
            style: style,
            avatarInputMode: avatarInputMode,
            selectedCatDefaultAvatarID: selectedCatDefaultAvatarID,
            selectedDogDefaultAvatarID: selectedDogDefaultAvatarID,
            referencePhotoRemotePath: referencePhotoRemotePath,
            generatedAvatarRemotePath: generatedAvatarRemotePath,
            avatarGenerationJobID: avatarGenerationJobID,
            avatarGenerationState: avatarGenerationState,
            avatarMessage: avatarMessage,
            defaultAvatarAssetName: selectedDefaultAvatarOption.artAsset.rawValue
        )
    }

    private func selectDefaultAvatar(id: String) {
        if species == "dog" {
            selectedDogDefaultAvatarID = id
        } else {
            selectedCatDefaultAvatarID = id
        }
    }

    private func syncPetSetupDraft() {
        appStore.applyPetSetupDraft(currentPetSetupDraft)
    }

    private func restoreDraftIfNeeded() {
        guard !hasRestoredDraft else { return }
        hasRestoredDraft = true

        guard let draft = appStore.petSetupDraft else {
            currentStep = initialStep
            return
        }

        petName = draft.petName
        ownerAlias = draft.ownerAlias
        species = draft.species
        style = draft.style
        avatarInputMode = draft.avatarInputMode
        selectedCatDefaultAvatarID = draft.selectedCatDefaultAvatarID
        selectedDogDefaultAvatarID = draft.selectedDogDefaultAvatarID
        referencePhotoRemotePath = draft.referencePhotoRemotePath
        generatedAvatarRemotePath = draft.generatedAvatarRemotePath
        avatarGenerationJobID = draft.avatarGenerationJobID
        avatarGenerationState = draft.avatarGenerationState
        avatarMessage = draft.avatarMessage
        currentStep = initialStep
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case 0, 1:
            return "下一步"
        default:
            return "完成建档"
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        isSubmitting
    }

    private var stepOneBlocker: StepOneBlocker? {
        if trimmedPetName.isEmpty {
            return .petNameMissing
        }

        if trimmedOwnerAlias.isEmpty {
            return .ownerAliasMissing
        }

        if isUsingDefaultAvatar {
            return nil
        }

        if avatarGenerationState == .generating {
            return .avatarGenerating
        }

        if referencePhotoRemotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .avatarPhotoMissing
        }

        if avatarGenerationState != .generated || generatedAvatarRemotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .avatarGenerationFailed
        }

        return nil
    }

    private func bottomActionBar(scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if currentStep > 0 {
                    Button("上一步") {
                        let previousStep = max(currentStep - 1, 0)
                        syncPetSetupDraft()
                        withAnimation(.easeInOut(duration: 0.22)) {
                            currentStep = previousStep
                        }
                        appStore.onboardingRoute = .petSetup(step: previousStep)
                    }
                    .buttonStyle(PetPalSecondaryButtonStyle())
                    .frame(width: 118)
                }

                Button {
                    handlePrimaryAction(scrollProxy: scrollProxy)
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

            Text("先填写基础信息，再上传照片生成头像，或直接使用默认头像。")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)

            VStack(alignment: .leading, spacing: 8) {
                PetPalFieldLabel(title: "名字", required: true)

                TextField("例如：团团、年糕、栗子、十一", text: $petName)
                    .petPalTextFieldStyle(isInvalid: stepOneFieldError(for: .petName) != nil)
                    .focused($focusedField, equals: .petName)
                    .accessibilityFocused($accessibilityFocusedField, equals: .petName)
                    .accessibilityLabel("宠物名字输入框")
                    .accessibilityHint("必填，给它起个名字")

                if let message = stepOneFieldError(for: .petName) {
                    PetPalInlineFeedback(message: message, tone: .warning)
                }
            }
            .id(StepOneScrollTarget.petName.rawValue)

            VStack(alignment: .leading, spacing: 8) {
                PetPalFieldLabel(title: "它怎么称呼你", required: true)

                TextField("例如：人类、铲屎官、妈咪、小主", text: $ownerAlias)
                    .petPalTextFieldStyle(isInvalid: stepOneFieldError(for: .ownerAlias) != nil)
                    .focused($focusedField, equals: .ownerAlias)
                    .accessibilityFocused($accessibilityFocusedField, equals: .ownerAlias)
                    .accessibilityLabel("宠物主人称呼输入框")
                    .accessibilityHint("必填，告诉它怎么称呼你")

                if let message = stepOneFieldError(for: .ownerAlias) {
                    PetPalInlineFeedback(message: message, tone: .warning)
                }
            }
            .id(StepOneScrollTarget.ownerAlias.rawValue)

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
        VStack(alignment: .leading, spacing: 10) {
            Text("宠物头像")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)

            stepOneArtworkCard(isCompactLayout: isCompactLayout, viewportHeight: viewportHeight)
        }
    }

    @ViewBuilder
    private func stepTwoContent(contentWidth: CGFloat, isCompactLayout: Bool, scrollProxy: ScrollViewProxy) -> some View {
        PetSetupStepHeader(
            eyebrow: nil,
            title: "对话风格",
            subtitle: "选一种聊天语气，让它更像你熟悉的样子。",
            chipText: nil,
            stampAsset: currentHeroArtAsset,
            stampImageURL: currentHeroImageURL
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
    private func stepOneArtworkCard(isCompactLayout _: Bool, viewportHeight _: CGFloat) -> some View {
        PetPalSurfaceCard {
            Text("上传照片生成专属头像，或直接使用默认头像。")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)

            avatarInputModeSelector()

            VStack(spacing: 14) {
                if isUsingDefaultAvatar {
                    defaultAvatarGrid()
                } else {
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
                                accentAsset: selectedSpecies.artAsset
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("打开系统照片选择器选择宠物参考照片")
                    case .generating:
                        PetSetupAvatarLoadingCard()
                    case .generated:
                        PetSetupArtworkPreview(
                            remoteImageURL: generatedAvatarResolvedURL,
                            fallbackAsset: selectedSpecies.artAsset,
                            onReplacePhoto: presentReferencePhotoPicker,
                            onRemoveAvatar: removeGeneratedAvatar
                        )
                    case .failed:
                        PetSetupAvatarPlaceholder(
                            title: "这次没有成功生成卡通形象",
                            subtitle: avatarMessage?.ifEmpty("换一张照片再试试，会更稳妥。") ?? "换一张照片再试试，会更稳妥。",
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
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    switch avatarGenerationState {
                    case .failed:
                        avatarReplacePhotoButton(title: "重新选择照片")
                    default:
                        EmptyView()
                    }
                }

                if let avatarValidationMessage {
                    PetPalInlineFeedback(message: avatarValidationMessage, tone: .warning)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(avatarBorderColor, lineWidth: 1.2)
        )
        .id(StepOneScrollTarget.avatar.rawValue)
    }

    @ViewBuilder
    private func avatarInputModeSelector() -> some View {
        HStack(spacing: 10) {
            avatarInputModeButton(
                mode: .photoGenerated,
                artAsset: .avatarPalette,
                title: "照片生成"
            )

            avatarInputModeButton(
                mode: .defaultArt,
                artAsset: selectedDefaultAvatarOption.artAsset,
                title: "默认头像"
            )
        }
    }

    private func avatarInputModeButton(
        mode: AvatarInputMode,
        artAsset: PetPalArtAsset,
        title: String
    ) -> some View {
        Button {
            errorMessage = nil
            avatarInputMode = mode
        } label: {
            PetPalAvatarSurface(isSelected: avatarInputMode == mode, cornerRadius: 18) {
                HStack(spacing: 10) {
                    PetPalArtImage(asset: artAsset)
                        .frame(width: 24, height: 24)

                    Text(title)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .padding(.horizontal, 12)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func defaultAvatarGrid() -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            ForEach(visibleDefaultAvatarOptions) { option in
                Button {
                    errorMessage = nil
                    selectDefaultAvatar(id: option.id)
                } label: {
                    defaultAvatarTile(option: option, isSelected: option.id == selectedDefaultAvatarID)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func defaultAvatarTile(option: DefaultAvatarOption, isSelected: Bool) -> some View {
        PetPalAvatarSurface(isSelected: isSelected, cornerRadius: 22) {
            VStack(spacing: 10) {
                ZStack {
                    RadialGradient(
                        colors: [PetPalTheme.avatarHalo.opacity(isSelected ? 0.42 : 0.26), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 60
                    )
                    .frame(width: 96, height: 96)

                    PetPalArtImage(asset: option.artAsset)
                        .frame(width: 68, height: 68)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)

                Text(option.title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
        }
    }

    private func avatarReplacePhotoButton(title: String) -> some View {
        Button(title) {
            presentReferencePhotoPicker()
        }
        .buttonStyle(PetPalSecondaryButtonStyle())
    }

    private func presentReferencePhotoPicker() {
        errorMessage = nil
        isShowingReferencePhotoPicker = true
    }

    private func removeGeneratedAvatar() {
        errorMessage = nil
        cancelAvatarGenerationPolling()
        avatarInputMode = .photoGenerated
        selectedReferencePhotoItem = nil
        cleanupReferencePhotoFile()
        referencePhotoRemotePath = ""
        generatedAvatarRemotePath = ""
        avatarGenerationJobID = ""
        avatarGenerationState = .idle
        avatarMessage = "已移除当前头像，请重新选择照片。"
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
        PetPalAvatarSurface(isSelected: isSelected, cornerRadius: 18) {
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
        }
    }

    @ViewBuilder
    private func optionTile(
        artAsset: PetPalArtAsset,
        title: String,
        subtitle: String,
        isSelected: Bool
    ) -> some View {
        PetPalAvatarSurface(isSelected: isSelected, cornerRadius: 22) {
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
        }
    }

    private var avatarValidationMessage: String? {
        guard hasAttemptedStepOneSubmit, currentStep == 0, stepOneBlocker?.isAvatarRelated == true else {
            return nil
        }

        return stepOneBlocker?.inlineMessage
    }

    private func stepOneFieldError(for field: StepOneFocusableField) -> String? {
        guard hasAttemptedStepOneSubmit, currentStep == 0 else { return nil }

        switch field {
        case .petName:
            return trimmedPetName.isEmpty ? "给它起个名字吧，这样才能继续设置聊天人格。" : nil
        case .ownerAlias:
            return trimmedOwnerAlias.isEmpty ? "告诉它怎么称呼你，聊天时会更像你们平时说话。" : nil
        }
    }

    private var avatarBorderColor: Color {
        if avatarValidationMessage != nil {
            return PetPalTheme.danger.opacity(0.75)
        }

        if isUsingDefaultAvatar {
            return Color(hex: "EDA579")
        }

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

    private func handlePrimaryAction(scrollProxy: ScrollViewProxy) {
        errorMessage = nil

        switch currentStep {
        case 0:
            advanceFromStepOne(scrollProxy: scrollProxy)
        default:
            Task {
                await createPet(scrollProxy: scrollProxy)
            }
        }
    }

    private func persistDraftAndNavigateToCamera() {
        let draft = currentPetSetupDraft
        appStore.applyPetSetupDraft(draft)
        appStore.applyPetSetupDraftToSession(draft)
        appStore.onboardingRoute = .cameraSetup
    }

    private func advanceFromStepOne(scrollProxy: ScrollViewProxy) {
        errorMessage = nil
        hasAttemptedStepOneSubmit = true

        if let blocker = stepOneBlocker {
            presentStepOneBlocker(blocker, scrollProxy: scrollProxy)
            return
        }

        focusedField = nil
        syncPetSetupDraft()
        withAnimation(.easeInOut(duration: 0.22)) {
            currentStep = 1
        }
        appStore.onboardingRoute = .petSetup(step: 1)
    }

    private func presentStepOneBlocker(_ blocker: StepOneBlocker, scrollProxy: ScrollViewProxy) {
        PetPalHaptics.warning()

        withAnimation(.easeInOut(duration: 0.22)) {
            scrollProxy.scrollTo(blocker.scrollTarget.rawValue, anchor: .center)
        }

        guard let focusField = blocker.focusField else {
            focusedField = nil
            accessibilityFocusedField = nil
            return
        }

        focusedField = focusField

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            accessibilityFocusedField = focusField
        }
    }

    private func returnToStepOne(with blocker: StepOneBlocker, scrollProxy: ScrollViewProxy) {
        hasAttemptedStepOneSubmit = true

        withAnimation(.easeInOut(duration: 0.22)) {
            currentStep = 0
        }
        syncPetSetupDraft()
        appStore.onboardingRoute = .petSetup(step: 0)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            presentStepOneBlocker(blocker, scrollProxy: scrollProxy)
        }
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
            cancelAvatarGenerationPolling()
            cleanupReferencePhotoFile()
            avatarInputMode = .photoGenerated
            referencePhotoLocalURL = copiedURL
            referencePhotoRemotePath = ""
            generatedAvatarRemotePath = ""
            avatarGenerationJobID = ""
            avatarGenerationState = .generating
            avatarMessage = "照片已上传，正在生成头像..."
            await generateAvatar(from: copiedURL)
        } catch {
            errorMessage = "导入参考照片失败：\(error.localizedDescription)"
        }
    }

    private func generateAvatar(from localURL: URL) async {
        cancelAvatarGenerationPolling()
        avatarGenerationState = .generating
        avatarMessage = "照片已上传，正在创建生成任务..."

        do {
            let response = try await appStore.apiClient.generatePetAvatar(
                species: species,
                imageFileURL: localURL
            )
            applyAvatarGenerationResponse(response)

            if !response.status.isTerminal {
                guard let jobID = normalizedAvatarGenerationJobID(from: response.jobID) else {
                    avatarGenerationState = .failed
                    avatarMessage = "头像任务已创建，但未返回任务编号，请重新试一次。"
                    return
                }
                avatarGenerationJobID = jobID
                startAvatarGenerationPolling(jobID: jobID)
            }
        } catch {
            avatarGenerationState = .failed
            avatarMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func normalizedAvatarGenerationJobID(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func applyAvatarGenerationResponse(_ response: GeneratedPetAvatarResponse) {
        if !response.photoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            referencePhotoRemotePath = response.photoURL
        }

        if !response.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            generatedAvatarRemotePath = response.avatarURL
        }

        if let jobID = normalizedAvatarGenerationJobID(from: response.jobID) {
            avatarGenerationJobID = jobID
        }

        switch response.status {
        case .queued:
            avatarGenerationState = .generating
            avatarMessage = "照片已上传，正在排队生成头像..."
        case .processing:
            avatarGenerationState = .generating
            avatarMessage = "正在生成头像..."
        case .completed:
            cancelAvatarGenerationPolling()
            avatarGenerationJobID = ""

            if response.avatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                avatarGenerationState = .failed
                avatarMessage = response.generationError?.ifEmpty("卡通形象暂时生成失败，但参考照片已经保存。") ?? "卡通形象暂时生成失败，但参考照片已经保存。"
            } else {
                avatarGenerationState = .generated
                avatarMessage = "头像已生成，可以继续下一步。"
            }
        case .failed:
            cancelAvatarGenerationPolling()
            avatarGenerationJobID = ""
            avatarGenerationState = .failed
            avatarMessage = response.generationError?.ifEmpty("卡通形象暂时生成失败，但参考照片已经保存。") ?? "卡通形象暂时生成失败，但参考照片已经保存。"
        }
    }

    private func resumeAvatarGenerationPollingIfNeeded() {
        guard avatarGenerationState == .generating else { return }
        guard let jobID = normalizedAvatarGenerationJobID(from: avatarGenerationJobID) else { return }
        startAvatarGenerationPolling(jobID: jobID)
    }

    private func cancelAvatarGenerationPolling() {
        avatarPollingTask?.cancel()
        avatarPollingTask = nil
    }

    private func startAvatarGenerationPolling(jobID: String) {
        cancelAvatarGenerationPolling()

        avatarPollingTask = Task { @MainActor in
            var consecutiveFailures = 0

            while !Task.isCancelled {
                do {
                    let response = try await appStore.apiClient.fetchPetAvatarGenerationJob(jobID: jobID)
                    consecutiveFailures = 0
                    applyAvatarGenerationResponse(response)

                    if response.status.isTerminal {
                        avatarPollingTask = nil
                        return
                    }
                } catch {
                    if Task.isCancelled {
                        avatarPollingTask = nil
                        return
                    }

                    consecutiveFailures += 1

                    if consecutiveFailures >= avatarPollingMaxFailures {
                        avatarGenerationState = .failed
                        avatarGenerationJobID = ""
                        avatarMessage = (error as? APIError)?.errorDescription ?? "头像生成状态查询失败，请稍后重试。"
                        avatarPollingTask = nil
                        return
                    }

                    avatarGenerationState = .generating
                    avatarMessage = "正在继续查询头像生成进度..."
                }

                do {
                    try await Task.sleep(nanoseconds: avatarPollingIntervalNanoseconds)
                } catch {
                    avatarPollingTask = nil
                    return
                }
            }

            avatarPollingTask = nil
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

    private func createPet(scrollProxy: ScrollViewProxy) async {
        guard let userID = appStore.session.userId else { return }

        if let blocker = stepOneBlocker {
            returnToStepOne(with: blocker, scrollProxy: scrollProxy)
            return
        }

        if appStore.session.petId != nil {
            errorMessage = nil
            persistDraftAndNavigateToCamera()
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            let request = CreatePetRequest(
                userID: userID,
                name: trimmedPetName,
                species: species,
                photoURL: isUsingDefaultAvatar ? "" : referencePhotoRemotePath,
                avatarURL: isUsingDefaultAvatar ? "" : generatedAvatarRemotePath,
                usesDefaultAvatar: isUsingDefaultAvatar,
                languageStyle: style,
                ownerAlias: trimmedOwnerAlias
            )

            let response = try await appStore.apiClient.createPet(request)

            appStore.applyCreatedPet(
                response: response,
                name: trimmedPetName,
                species: species,
                style: style,
                ownerAlias: trimmedOwnerAlias,
                defaultAvatarAssetName: isUsingDefaultAvatar ? selectedDefaultAvatarOption.artAsset.rawValue : ""
            )
            persistDraftAndNavigateToCamera()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }
}

private struct PetSetupStepHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?
    let chipText: String?
    let stampAsset: PetPalArtAsset?
    let stampImageURL: URL?

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String? = nil,
        chipText: String? = nil,
        stampAsset: PetPalArtAsset? = nil,
        stampImageURL: URL? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.chipText = chipText
        self.stampAsset = stampAsset
        self.stampImageURL = stampImageURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if eyebrow != nil || chipText != nil {
                HStack(alignment: .center, spacing: 10) {
                    if let eyebrow {
                        Text(eyebrow)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(PetPalTheme.caramel)
                            .tracking(1)
                    }

                    if let chipText {
                        PetPalCapsuleLabel(text: chipText, style: .soft)
                            .scaleEffect(0.92, anchor: .leading)
                    }

                    Spacer(minLength: 8)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                if let stampAsset {
                    PetPalStamp(fallbackAsset: stampAsset, imageURL: stampImageURL)
                        .scaleEffect(0.82)
                        .frame(width: 58, height: 58)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(PetPalTheme.inkSoft)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct PetSetupImageCard: View {
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

struct PetSetupAvatarPlaceholder: View {
    let title: String
    let subtitle: String
    let accentAsset: PetPalArtAsset

    var body: some View {
        PetPalAvatarSurface(cornerRadius: 24) {
            VStack(spacing: 14) {
                ZStack {
                    RadialGradient(
                        colors: [PetPalTheme.avatarHalo.opacity(0.44), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 70
                    )
                    .frame(width: 92, height: 92)

                    PetPalArtImage(asset: accentAsset)
                        .frame(width: 48, height: 48)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PetSetupArtworkPreview: View {
    let remoteImageURL: URL?
    let fallbackAsset: PetPalArtAsset
    var onReplacePhoto: (() -> Void)? = nil
    var onRemoveAvatar: (() -> Void)? = nil

    var body: some View {
        PetPalAvatarSurface(cornerRadius: 24) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            if let onReplacePhoto, let onRemoveAvatar {
                Menu {
                    Button {
                        onReplacePhoto()
                    } label: {
                        Label("更换照片", systemImage: "photo")
                    }

                    Button(role: .destructive) {
                        onRemoveAvatar()
                    } label: {
                        Label("移除当前头像", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .black))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(PetPalIconGhostButtonStyle())
                .padding(12)
                .accessibilityLabel("头像更多操作")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let remoteImageURL {
            AsyncImage(url: remoteImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
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
        VStack(spacing: 10) {
            RadialGradient(
                colors: [PetPalTheme.avatarHalo.opacity(0.42), .clear],
                center: .center,
                startRadius: 8,
                endRadius: 64
            )
            .frame(width: 88, height: 88)
            .overlay {
                PetPalArtImage(asset: fallbackAsset)
                    .frame(width: 52, height: 52)
            }

            Text("等待图片")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)
        }
    }
}

struct PetSetupAvatarLoadingCard: View {
    var body: some View {
        PetPalAvatarSurface(cornerRadius: 24) {
            VStack(spacing: 14) {
                ZStack {
                    RadialGradient(
                        colors: [PetPalTheme.avatarHalo.opacity(0.46), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 70
                    )
                    .frame(width: 92, height: 92)

                    ProgressView()
                        .controlSize(.large)
                        .tint(Color(hex: "EF986A"))
                }

                VStack(spacing: 8) {
                    Text("正在生成头像")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)

                    Text("请稍等片刻，完成后可以继续下一步，或重新选择照片。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 24)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }
}

private enum StepOneFocusableField: Hashable {
    case petName
    case ownerAlias
}

private enum StepOneScrollTarget: String {
    case petName
    case ownerAlias
    case avatar
}

private enum StepOneBlocker: Equatable {
    case petNameMissing
    case ownerAliasMissing
    case avatarPhotoMissing
    case avatarGenerating
    case avatarGenerationFailed

    var scrollTarget: StepOneScrollTarget {
        switch self {
        case .petNameMissing:
            return .petName
        case .ownerAliasMissing:
            return .ownerAlias
        case .avatarPhotoMissing, .avatarGenerating, .avatarGenerationFailed:
            return .avatar
        }
    }

    var focusField: StepOneFocusableField? {
        switch self {
        case .petNameMissing:
            return .petName
        case .ownerAliasMissing:
            return .ownerAlias
        case .avatarPhotoMissing, .avatarGenerating, .avatarGenerationFailed:
            return nil
        }
    }

    var isAvatarRelated: Bool {
        switch self {
        case .avatarPhotoMissing, .avatarGenerating, .avatarGenerationFailed:
            return true
        case .petNameMissing, .ownerAliasMissing:
            return false
        }
    }

    var inlineMessage: String {
        switch self {
        case .petNameMissing:
            return "给它起个名字吧，这样才能继续设置聊天人格。"
        case .ownerAliasMissing:
            return "告诉它怎么称呼你，聊天时会更像你们平时说话。"
        case .avatarPhotoMissing:
            return "先选一张它的照片，我们会据此生成专属头像。"
        case .avatarGenerating:
            return "头像还在生成中，生成完成后就能继续下一步。"
        case .avatarGenerationFailed:
            return "头像这次还没准备好，换张照片后就能继续。"
        }
    }

}
struct SpeciesOption: Identifiable {
    let id: String
    let artAsset: PetPalArtAsset
    let label: String
    let summary: String
}

struct StyleOption: Identifiable {
    let id: String
    let artAsset: PetPalArtAsset
    let name: String
    let desc: String
}

struct DefaultAvatarOption: Identifiable {
    let id: String
    let species: String
    let artAsset: PetPalArtAsset
    let title: String
}

let petPalSpeciesOptions = [
    SpeciesOption(id: "cat", artAsset: .petCat, label: "喵星人", summary: "轻盈、敏感、会把心事藏在尾巴尖。"),
    SpeciesOption(id: "dog", artAsset: .petDog, label: "汪星人", summary: "热情、黏人、会把开心都写在眼睛里。"),
]

let petPalStyleOptions = [
    StyleOption(id: "tsundere", artAsset: .styleTsundere, name: "傲娇主子", desc: "嘴上不说，心里却记得你什么时候回家。"),
    StyleOption(id: "loyal", artAsset: .styleLoyal, name: "忠诚小跟班", desc: "每一句回应都像摇着尾巴朝你跑来。"),
    StyleOption(id: "chatty", artAsset: .styleChatty, name: "碎碎念搭子", desc: "芝麻大的小事，也想马上讲给你听。"),
    StyleOption(id: "chill", artAsset: .styleChill, name: "松弛感主角", desc: "不慌不忙，连撒娇都带着午后阳光味。"),
]

let petPalDefaultAvatarOptions = [
    DefaultAvatarOption(id: "cat_american_shorthair", species: "cat", artAsset: .petCat, title: "美短"),
    DefaultAvatarOption(id: "cat_british_shorthair", species: "cat", artAsset: .petCatBritish, title: "英短"),
    DefaultAvatarOption(id: "cat_siamese", species: "cat", artAsset: .petCatSiamese, title: "暹罗"),
    DefaultAvatarOption(id: "cat_ragdoll", species: "cat", artAsset: .petCatRagdoll, title: "布偶"),
    DefaultAvatarOption(id: "dog_beagle", species: "dog", artAsset: .petDog, title: "比格"),
    DefaultAvatarOption(id: "dog_corgi", species: "dog", artAsset: .petDogCorgi, title: "柯基"),
    DefaultAvatarOption(id: "dog_golden", species: "dog", artAsset: .petDogGolden, title: "金毛"),
    DefaultAvatarOption(id: "dog_shiba", species: "dog", artAsset: .petDogShiba, title: "柴犬"),
]

func petPalSpeciesName(for speciesID: String) -> String {
    speciesID == "dog" ? "狗狗" : "猫咪"
}

func petPalStyleName(for styleID: String) -> String {
    petPalStyleOptions.first(where: { $0.id == styleID })?.name ?? "傲娇主子"
}

func petPalDefaultAvatarID(for assetName: String, species: String) -> String {
    if let matched = petPalDefaultAvatarOptions.first(where: {
        $0.species == species && $0.artAsset.rawValue == assetName
    }) {
        return matched.id
    }

    return petPalDefaultAvatarOptions.first(where: { $0.species == species })?.id
        ?? (species == "dog" ? "dog_beagle" : "cat_american_shorthair")
}
