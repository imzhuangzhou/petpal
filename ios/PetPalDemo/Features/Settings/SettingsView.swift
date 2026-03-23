import AVKit
import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideo: PickedVideo?
    @State private var isUploadingVideo = false
    @State private var isShowingResetConfirmation = false
    @State private var videoErrorMessage: String?

    @State private var isEditingPet = false
    @State private var isSavingPet = false
    @State private var isSyncingPetEditor = false
    @State private var petErrorMessage: String?
    @State private var petName = ""
    @State private var ownerAlias = ""
    @State private var species = "cat"
    @State private var style = "tsundere"
    @State private var avatarInputMode: AvatarInputMode = .photoGenerated
    @State private var selectedCatDefaultAvatarID = "cat_american_shorthair"
    @State private var selectedDogDefaultAvatarID = "dog_beagle"
    @State private var selectedReferencePhotoItem: PhotosPickerItem?
    @State private var isShowingReferencePhotoPicker = false
    @State private var referencePhotoLocalURL: URL?
    @State private var referencePhotoRemotePath = ""
    @State private var generatedAvatarRemotePath = ""
    @State private var avatarGenerationState: AvatarGenerationState = .idle
    @State private var avatarMessage: String?

    private let speciesOptions = petPalSpeciesOptions
    private let styleOptions = petPalStyleOptions
    private let defaultAvatarOptions = petPalDefaultAvatarOptions
    private let referencePhotoMaxDimension: CGFloat = 1600
    private let referencePhotoCompressionQuality: CGFloat = 0.85

    var body: some View {
        PetPalShell {
            VStack(spacing: 16) {
                PetPalNavigationHeader(
                    title: "设置",
                    onBack: { dismiss() }
                )
                .padding(.horizontal, 20)

                ZStack {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            petInfoSection
                            cameraSection
                            resetSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    if isUploadingVideo {
                        PetPalLoadingOverlay(
                            title: "正在更新联调视频...",
                            subtitle: "新的摄像头上下文会在上传完成后立即生效。"
                        )
                    } else if isSavingPet {
                        PetPalLoadingOverlay(
                            title: "正在更新宠物资料...",
                            subtitle: "保存后聊天风格和宠物档案会立刻刷新。"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .alert("确认重置当前配置？", isPresented: $isShowingResetConfirmation) {
            Button("确认重置", role: .destructive) {
                appStore.reset()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清空当前宠物和摄像头相关配置。")
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            syncPetEditorFromSession()
        }
        .onChange(of: selectedVideoItem) {
            Task {
                await loadSelectedVideo()
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
        .onChange(of: species) { oldValue, newValue in
            handleSpeciesChange(from: oldValue, to: newValue)
        }
        .onDisappear {
            cleanupReferencePhotoFile()
        }
    }

    private var petInfoSection: some View {
        PetPalPanelCard {
            PetPalSectionHeader(
                eyebrow: "宠物信息",
                title: isEditingPet ? petName.ifEmpty(appStore.session.petName.ifEmpty("PetPal")) : appStore.session.petName.ifEmpty("PetPal"),
                chipText: isEditingPet ? "编辑中" : nil
            )

            if isEditingPet {
                petEditorCard
            } else {
                petSummaryCard
            }
        }
    }

    private var petSummaryCard: some View {
        VStack(spacing: 12) {
            PetPalSurfaceCard {
                PetPalInfoRow(
                    title: "主人",
                    value: appStore.session.ownerAlias.ifEmpty(appStore.session.nickname.ifEmpty("你"))
                )
                PetPalInfoRow(
                    title: "种类",
                    value: petPalSpeciesName(for: appStore.session.petSpecies)
                )
                PetPalInfoRow(
                    title: "聊天风格",
                    value: petPalStyleName(for: appStore.session.languageStyle)
                )
                PetPalInfoRow(
                    title: "头像来源",
                    value: appStore.session.petDefaultAvatarAssetName.isEmpty ? "照片生成" : "默认头像"
                )
            }

            Button("编辑宠物信息") {
                beginPetEditing()
            }
            .buttonStyle(PetPalPrimaryButtonStyle())
        }
    }

    private var petEditorCard: some View {
        PetPalSurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    PetPalFieldLabel(title: "名字", required: true)

                    TextField("例如：发财、奶盖、奥利奥...", text: $petName)
                        .petPalTextFieldStyle(isInvalid: trimmedPetName.isEmpty)
                }

                VStack(alignment: .leading, spacing: 8) {
                    PetPalFieldLabel(title: "它怎么称呼你", required: true)

                    TextField("例如：boss、妈妈、小陈...", text: $ownerAlias)
                        .petPalTextFieldStyle(isInvalid: trimmedOwnerAlias.isEmpty)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("宠物种类")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)

                    HStack(spacing: 12) {
                        ForEach(speciesOptions) { option in
                            Button {
                                species = option.id
                                petErrorMessage = nil
                            } label: {
                                speciesTile(option: option, isSelected: species == option.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("聊天风格")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        ForEach(styleOptions) { option in
                            Button {
                                style = option.id
                                petErrorMessage = nil
                            } label: {
                                styleTile(option: option, isSelected: style == option.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("宠物头像")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)

                    Text("直接切换默认头像，或重新上传照片生成新的宠物形象。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .lineSpacing(3)

                    avatarInputModeSelector

                    if isUsingDefaultAvatar {
                        defaultAvatarGrid
                    } else {
                        photoAvatarEditor
                    }
                }

                if let petValidationMessage {
                    PetPalInlineFeedback(message: petValidationMessage, tone: .warning)
                }

                if let petErrorMessage {
                    PetPalInlineFeedback(message: petErrorMessage, tone: .danger)
                }

                HStack(spacing: 10) {
                    Button("取消") {
                        cancelPetEditing()
                    }
                    .buttonStyle(PetPalSecondaryButtonStyle())

                    Button {
                        Task {
                            await savePetProfile()
                        }
                    } label: {
                        Group {
                            if isSavingPet {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("保存宠物信息")
                            }
                        }
                    }
                    .buttonStyle(PetPalPrimaryButtonStyle())
                    .disabled(isSavingPet || petValidationMessage != nil)
                }
            }
        }
    }

    private var cameraSection: some View {
        PetPalPanelCard {
            PetPalSectionHeader(
                eyebrow: "摄像头",
                title: "视频上下文",
                chipText: nil
            )

            PetPalSurfaceCard {
                PetPalInfoRow(
                    title: "当前摄像头",
                    value: appStore.session.cameraName.ifEmpty("未绑定")
                )

                PetPalInfoRow(
                    title: "联调视频",
                    value: appStore.session.demoVideoName.ifEmpty("未上传")
                )

                if let selectedVideo {
                    Text("待上传视频：\(selectedVideo.url.lastPathComponent)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)
                }

                if let previewURL = selectedPreviewURL {
                    PetPalPlayableVideoView(url: previewURL)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if showsVideoAnalysisDebugEntry, let cameraID = appStore.session.cameraId {
                    NavigationLink {
                        VideoAnalysisDebugView(cameraID: cameraID)
                    } label: {
                        Label("视频分析测试页", systemImage: "ladybug.fill")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                    }
                    .buttonStyle(PetPalSecondaryButtonStyle())
                }

                PhotosPicker(
                    selection: $selectedVideoItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Text(selectedVideo == nil ? "从相册选择新视频" : "从相册重新选择视频")
                }
                .buttonStyle(PetPalSecondaryButtonStyle())

                if selectedVideo != nil {
                    Button {
                        Task {
                            await replaceVideo()
                        }
                    } label: {
                        Group {
                            if isUploadingVideo {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("上传更新")
                            }
                        }
                    }
                    .buttonStyle(PetPalPrimaryButtonStyle())
                    .disabled(
                        isUploadingVideo ||
                        appStore.session.userId == nil ||
                        appStore.session.petId == nil
                    )
                }

                if let videoErrorMessage {
                    Text(videoErrorMessage)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.danger)
                }
            }
        }
    }

    private var resetSection: some View {
        PetPalPanelCard {
            PetPalSectionHeader(
                eyebrow: "通用",
                title: "重置当前配置",
                chipText: nil
            )

            Button("重置当前配置", role: .destructive) {
                isShowingResetConfirmation = true
            }
            .buttonStyle(PetPalDangerButtonStyle())
        }
    }

    private var selectedPreviewURL: URL? {
        if let selectedVideo {
            return selectedVideo.url
        }

        if let bundledURL = petPalBundledDemoVideoURL(named: appStore.session.demoVideoName) {
            return bundledURL
        }

        return appStore.apiClient.resolvedURL(for: appStore.session.demoVideoURL)
    }

    private var showsVideoAnalysisDebugEntry: Bool {
        appStore.session.cameraId != nil &&
        !appStore.session.demoVideoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var trimmedPetName: String {
        petName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedOwnerAlias: String {
        ownerAlias.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUsingDefaultAvatar: Bool {
        avatarInputMode == .defaultArt
    }

    private var visibleDefaultAvatarOptions: [DefaultAvatarOption] {
        defaultAvatarOptions.filter { $0.species == species }
    }

    private var selectedDefaultAvatarID: String {
        species == "dog" ? selectedDogDefaultAvatarID : selectedCatDefaultAvatarID
    }

    private var selectedDefaultAvatarOption: DefaultAvatarOption {
        visibleDefaultAvatarOptions.first(where: { $0.id == selectedDefaultAvatarID }) ?? visibleDefaultAvatarOptions[0]
    }

    private var selectedSpeciesOption: SpeciesOption {
        speciesOptions.first(where: { $0.id == species }) ?? speciesOptions[0]
    }

    private var generatedAvatarResolvedURL: URL? {
        appStore.apiClient.resolvedURL(for: generatedAvatarRemotePath)
    }

    private var referencePhotoResolvedURL: URL? {
        appStore.apiClient.resolvedURL(for: referencePhotoRemotePath)
    }

    private var petValidationMessage: String? {
        if trimmedPetName.isEmpty {
            return "给它起个名字吧，这样聊天和设置里都会更清楚。"
        }

        if trimmedOwnerAlias.isEmpty {
            return "告诉它怎么称呼你，保存后后续聊天会直接生效。"
        }

        if isUsingDefaultAvatar {
            return nil
        }

        switch avatarGenerationState {
        case .generating:
            return "头像还在生成中，生成完成后就能保存。"
        case .generated:
            return generatedAvatarRemotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "头像还没准备好，请重新选择照片生成。"
                : nil
        case .idle:
            return referencePhotoRemotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "当前是照片生成模式，请先选择一张新照片。"
                : "请通过右上角菜单重新选择照片，或移除当前头像。"
        case .failed:
            return "头像生成失败了，换张照片后才能保存。"
        }
    }

    private var avatarInputModeSelector: some View {
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

    private var defaultAvatarGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            ForEach(visibleDefaultAvatarOptions) { option in
                Button {
                    petErrorMessage = nil
                    selectDefaultAvatar(id: option.id)
                } label: {
                    defaultAvatarTile(option: option, isSelected: option.id == selectedDefaultAvatarID)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var photoAvatarEditor: some View {
        switch avatarGenerationState {
        case .idle:
            if referencePhotoRemotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PhotosPicker(
                    selection: $selectedReferencePhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    PetSetupAvatarPlaceholder(
                        title: "上传宠物照片",
                        subtitle: "更换种类后需要重新选择一张清晰照片。",
                        accentAsset: selectedSpeciesOption.artAsset
                    )
                }
                .buttonStyle(.plain)
            } else {
                PetSetupArtworkPreview(
                    remoteImageURL: generatedAvatarResolvedURL ?? referencePhotoResolvedURL,
                    fallbackAsset: selectedSpeciesOption.artAsset,
                    onReplacePhoto: presentReferencePhotoPicker,
                    onRemoveAvatar: removeCurrentAvatar
                )
            }
        case .generating:
            PetSetupAvatarLoadingCard()
        case .generated:
            PetSetupArtworkPreview(
                remoteImageURL: generatedAvatarResolvedURL,
                fallbackAsset: selectedSpeciesOption.artAsset,
                onReplacePhoto: presentReferencePhotoPicker,
                onRemoveAvatar: removeCurrentAvatar
            )
        case .failed:
            PetSetupAvatarPlaceholder(
                title: "这次没有成功生成卡通形象",
                subtitle: avatarMessage?.ifEmpty("换一张照片再试试，会更稳妥。") ?? "换一张照片再试试，会更稳妥。",
                accentAsset: .avatarPalette
            )

            avatarReplacePhotoButton(title: "重新选择照片")
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
    }

    private func avatarInputModeButton(
        mode: AvatarInputMode,
        artAsset: PetPalArtAsset,
        title: String
    ) -> some View {
        Button {
            avatarInputMode = mode
            petErrorMessage = nil
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

    private func speciesTile(option: SpeciesOption, isSelected: Bool) -> some View {
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

    private func styleTile(option: StyleOption, isSelected: Bool) -> some View {
        PetPalAvatarSurface(isSelected: isSelected, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                PetPalArtImage(asset: option.artAsset)
                    .frame(width: 34, height: 34)

                Text(option.name)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)

                Text(option.desc)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

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
        petErrorMessage = nil
        isShowingReferencePhotoPicker = true
    }

    private func removeCurrentAvatar() {
        petErrorMessage = nil
        avatarInputMode = .photoGenerated
        selectedReferencePhotoItem = nil
        cleanupReferencePhotoFile()
        referencePhotoRemotePath = ""
        generatedAvatarRemotePath = ""
        avatarGenerationState = .idle
        avatarMessage = "已移除当前头像，请重新选择照片。"
    }

    private func beginPetEditing() {
        syncPetEditorFromSession()
        petErrorMessage = nil
        isEditingPet = true
    }

    private func cancelPetEditing() {
        petErrorMessage = nil
        isEditingPet = false
        syncPetEditorFromSession()
    }

    private func syncPetEditorFromSession() {
        isSyncingPetEditor = true
        cleanupReferencePhotoFile()

        let session = appStore.session
        petName = session.petName
        ownerAlias = session.ownerAlias
        species = session.petSpecies.ifEmpty("cat")
        style = session.languageStyle.ifEmpty("tsundere")

        selectedCatDefaultAvatarID = "cat_american_shorthair"
        selectedDogDefaultAvatarID = "dog_beagle"
        if !session.petDefaultAvatarAssetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let mappedID = petPalDefaultAvatarID(
                for: session.petDefaultAvatarAssetName,
                species: session.petSpecies.ifEmpty("cat")
            )
            if session.petSpecies == "dog" {
                selectedDogDefaultAvatarID = mappedID
            } else {
                selectedCatDefaultAvatarID = mappedID
            }
        }

        let usesDefaultAvatar = !session.petDefaultAvatarAssetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        avatarInputMode = usesDefaultAvatar ? .defaultArt : .photoGenerated
        referencePhotoRemotePath = usesDefaultAvatar ? "" : session.petPhotoURL
        generatedAvatarRemotePath = usesDefaultAvatar ? "" : session.petAvatarURL
        avatarGenerationState = usesDefaultAvatar ? .idle : (
            session.petAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .idle : .generated
        )
        avatarMessage = usesDefaultAvatar ? nil : (
            session.petAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "选择一张新照片后，就能生成专属头像。"
                : "当前头像已同步，重新选照片后会覆盖成新的形象。"
        )
        petErrorMessage = nil

        isSyncingPetEditor = false
    }

    private func handleSpeciesChange(from oldValue: String, to newValue: String) {
        guard oldValue != newValue, !isSyncingPetEditor else { return }

        petErrorMessage = nil

        if avatarInputMode == .photoGenerated {
            cleanupReferencePhotoFile()
            referencePhotoRemotePath = ""
            generatedAvatarRemotePath = ""
            avatarGenerationState = .idle
            avatarMessage = "已切换为\(petPalSpeciesName(for: newValue))，请重新选择照片生成头像。"
        } else {
            avatarMessage = "已切换为\(petPalSpeciesName(for: newValue))，下方默认头像已同步更新。"
        }
    }

    private func selectDefaultAvatar(id: String) {
        if species == "dog" {
            selectedDogDefaultAvatarID = id
        } else {
            selectedCatDefaultAvatarID = id
        }
    }

    private func loadSelectedVideo() async {
        videoErrorMessage = nil

        guard let selectedVideoItem else {
            selectedVideo = nil
            return
        }

        do {
            selectedVideo = try await selectedVideoItem.loadTransferable(type: PickedVideo.self)
        } catch {
            selectedVideo = nil
            videoErrorMessage = "无法读取所选视频，请重新选择。"
        }
    }

    private func replaceVideo() async {
        guard
            let userID = appStore.session.userId,
            let petID = appStore.session.petId,
            let selectedVideo
        else {
            return
        }

        isUploadingVideo = true
        videoErrorMessage = nil

        do {
            let response = try await appStore.apiClient.uploadDemoVideo(
                DemoVideoUploadRequest(
                    userID: userID,
                    petID: petID,
                    cameraName: appStore.session.cameraName.ifEmpty("家庭摄像头"),
                    cameraID: appStore.session.cameraId,
                    videoFileURL: selectedVideo.url
                )
            )
            appStore.applyUploadedDemoVideo(response)
            self.selectedVideo = nil
        } catch {
            videoErrorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isUploadingVideo = false
    }

    private func savePetProfile() async {
        guard let petID = appStore.session.petId else { return }
        guard petValidationMessage == nil else { return }

        isSavingPet = true
        petErrorMessage = nil

        do {
            let response = try await appStore.apiClient.updatePet(
                petID: petID,
                requestBody: UpdatePetRequest(
                    name: trimmedPetName,
                    species: species,
                    photoURL: isUsingDefaultAvatar ? "" : referencePhotoRemotePath,
                    avatarURL: isUsingDefaultAvatar ? "" : generatedAvatarRemotePath,
                    usesDefaultAvatar: isUsingDefaultAvatar,
                    languageStyle: style,
                    ownerAlias: trimmedOwnerAlias
                )
            )

            appStore.applyUpdatedPet(
                response: response,
                fallbackName: trimmedPetName,
                fallbackOwnerAlias: trimmedOwnerAlias,
                defaultAvatarAssetName: isUsingDefaultAvatar ? selectedDefaultAvatarOption.artAsset.rawValue : ""
            )
            isEditingPet = false
            syncPetEditorFromSession()
        } catch {
            petErrorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSavingPet = false
    }

    private func importReferencePhoto() async {
        petErrorMessage = nil

        guard let selectedReferencePhotoItem else {
            return
        }
        defer { self.selectedReferencePhotoItem = nil }

        do {
            guard let photoData = try await selectedReferencePhotoItem.loadTransferable(type: Data.self) else {
                petErrorMessage = "无法读取你选择的图片，请重新试一次。"
                return
            }

            let copiedURL = try persistSelectedReferencePhoto(data: photoData)
            cleanupReferencePhotoFile()
            avatarInputMode = .photoGenerated
            referencePhotoLocalURL = copiedURL
            referencePhotoRemotePath = ""
            generatedAvatarRemotePath = ""
            avatarGenerationState = .generating
            avatarMessage = "照片已上传，正在生成头像..."
            await generateAvatar(from: copiedURL)
        } catch {
            petErrorMessage = "导入参考照片失败：\(error.localizedDescription)"
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
                avatarMessage = "头像已生成，保存后聊天页会立刻换成新的形象。"
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
}

private struct VideoAnalysisDebugView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let cameraID: Int

    @State private var debugData: VideoAnalysisDebugResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let frameColumns = [
        GridItem(.adaptive(minimum: 196, maximum: 280), spacing: 12, alignment: .top)
    ]

    var body: some View {
        PetPalShell {
            VStack(spacing: 16) {
                PetPalNavigationHeader(
                    title: "视频分析测试",
                    onBack: { dismiss() }
                ) {
                    Button {
                        Task {
                            await loadDebugData(showLoader: false)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .black))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(PetPalSmallGhostButtonStyle())
                    .accessibilityLabel("刷新调试数据")
                }
                .padding(.horizontal, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        currentVideoSection
                        processingSection
                        framesSection
                        eventsSection

                        if let errorMessage {
                            PetPalInlineFeedback(message: errorMessage, tone: .warning)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
                .scrollBounceBehavior(.basedOnSize)
                .refreshable {
                    await loadDebugData(showLoader: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadDebugData()
        }
    }

    private var currentVideoSection: some View {
        PetPalPanelCard {
            PetPalSectionHeader(
                eyebrow: "当前视频",
                title: currentVideoName,
                chipText: processingStatusTitle
            )

            if let videoURL = resolvedVideoURL {
                PetPalPlayableVideoView(url: videoURL)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                PetPalSurfaceCard {
                    Text("当前没有可预览的视频地址。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                }
            }

            PetPalSurfaceCard {
                DebugMetadataRow(
                    title: "Camera ID",
                    value: String(cameraID)
                )

                DebugMetadataRow(
                    title: "视频地址",
                    value: currentVideoPath
                )

                DebugMetadataRow(
                    title: "最后更新",
                    value: lastUpdatedText
                )

                if let contextSummary = debugData?.contextSummary,
                   !contextSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    Text(contextSummary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .lineSpacing(3)
                }
            }
        }
    }

    private var processingSection: some View {
        PetPalPanelCard {
            PetPalSectionHeader(
                eyebrow: "处理状态",
                title: "静态步骤结果",
                chipText: nil
            )

            if isLoading && debugData == nil {
                ProgressView("正在读取分析结果...")
                    .tint(PetPalTheme.caramel)
            } else if stepStates.isEmpty {
                PetPalSurfaceCard {
                    Text("当前还没有可展示的处理快照。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(stepStates) { step in
                        DebugStepRow(step: step)
                    }
                }
            }
        }
    }

    private var framesSection: some View {
        PetPalPanelCard {
            PetPalSectionHeader(
                eyebrow: "抽帧图片",
                title: "共 \(debugData?.frames.count ?? 0) 张",
                chipText: nil
            )

            if let debugData, !debugData.frames.isEmpty {
                if horizontalSizeClass == .compact {
                    VStack(spacing: 12) {
                        ForEach(debugData.frames) { frame in
                            DebugFrameCard(frame: frame)
                        }
                    }
                } else {
                    LazyVGrid(columns: frameColumns, alignment: .leading, spacing: 12) {
                        ForEach(debugData.frames) { frame in
                            DebugFrameCard(frame: frame)
                        }
                    }
                }
            } else {
                PetPalSurfaceCard {
                    Text("当前快照里还没有抽帧图片。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                }
            }
        }
    }

    private var eventsSection: some View {
        PetPalPanelCard {
            PetPalSectionHeader(
                eyebrow: "事件列表",
                title: "共 \(debugData?.events.count ?? 0) 条",
                chipText: nil
            )

            if let debugData, !debugData.events.isEmpty {
                VStack(spacing: 10) {
                    ForEach(debugData.events) { event in
                        DebugEventCard(event: event)
                    }
                }
            } else {
                PetPalSurfaceCard {
                    Text("当前 camera 还没有分析事件。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                }
            }
        }
    }

    private var stepStates: [VideoAnalysisDebugStep] {
        debugData?.stepStates ?? []
    }

    private var resolvedVideoURL: URL? {
        let path = (debugData?.demoVideoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (debugData?.demoVideoURL ?? "")
            : appStore.session.demoVideoURL
        let preferredName = (debugData?.demoVideoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? (debugData?.demoVideoName ?? "")
            : appStore.session.demoVideoName

        if let bundledURL = petPalBundledDemoVideoURL(named: preferredName) {
            return bundledURL
        }

        return appStore.apiClient.resolvedURL(for: path)
    }

    private var currentVideoName: String {
        let debugName = debugData?.demoVideoName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !debugName.isEmpty {
            return debugName
        }

        return appStore.session.demoVideoName.ifEmpty("未命名视频")
    }

    private var currentVideoPath: String {
        let debugPath = debugData?.demoVideoURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !debugPath.isEmpty {
            return debugPath
        }

        return appStore.session.demoVideoURL.ifEmpty("暂无")
    }

    private var lastUpdatedText: String {
        let updated = debugData?.lastUpdatedAt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return updated.isEmpty ? "暂无" : updated
    }

    private var processingStatusTitle: String {
        switch debugData?.processingStatus {
        case "completed":
            return "已完成"
        case "not_available":
            return "暂无快照"
        case .none:
            return isLoading ? "加载中" : "待读取"
        default:
            return "开发态"
        }
    }

    @MainActor
    private func loadDebugData(showLoader: Bool = true) async {
        if showLoader {
            isLoading = true
        }
        errorMessage = nil

        do {
            debugData = try await appStore.apiClient.fetchVideoAnalysisDebug(cameraID: cameraID)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}

private struct DebugMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)

            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DebugStepRow: View {
    let step: VideoAnalysisDebugStep

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(step.state == "completed" ? PetPalTheme.mint : Color(hex: "F5E8D7"))
                    .frame(width: 32, height: 32)

                Image(systemName: step.state == "completed" ? "checkmark" : "ellipsis")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(step.state == "completed" ? PetPalTheme.success : PetPalTheme.inkSoft)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)

                Text(step.state == "completed" ? "已完成" : "未完成")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(hex: "FFF8EE").opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PetPalTheme.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DebugFrameCard: View {
    @EnvironmentObject private var appStore: AppStore

    let frame: VideoAnalysisDebugFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color(hex: "FFF3E5"))
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    AsyncImage(url: resolvedFrameURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty, .failure:
                            ZStack {
                                Color.clear

                                Image(systemName: "photo")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(PetPalTheme.inkSoft)
                            }
                        @unknown default:
                            ZStack {
                                Color.clear

                                Image(systemName: "photo")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(PetPalTheme.inkSoft)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text("#\(frame.sequence)  \(frame.videoTimeText)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.caramel)

                Text(frame.eventType.ifEmpty("other"))
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .lineLimit(1)

                Text(frame.description.ifEmpty("暂无描述"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "FFF8EE").opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PetPalTheme.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resolvedFrameURL: URL? {
        appStore.apiClient.resolvedURL(for: frame.frameURL)
    }
}

private struct DebugEventCard: View {
    @EnvironmentObject private var appStore: AppStore

    let event: VideoAnalysisDebugEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                AsyncImage(url: resolvedFrameURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        ZStack {
                            Color(hex: "FFF3E5")
                            Image(systemName: "film.stack")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(PetPalTheme.inkSoft)
                        }
                    }
                }
            }
            .frame(width: 84, height: 84)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.eventType.ifEmpty("other"))
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)
                        .lineLimit(1)

                    Text(event.timestamp)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .lineLimit(2)
                }

                Text(event.description)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text("持续 \(Int(event.durationSeconds)) 秒")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.caramel)

                if let clipRangeText {
                    Text("片段 \(clipRangeText)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "FFF8EE").opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PetPalTheme.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resolvedFrameURL: URL? {
        appStore.apiClient.resolvedURL(for: event.frameURL)
    }

    private var clipRangeText: String? {
        guard let start = event.videoStartSeconds, let end = event.videoEndSeconds else {
            return nil
        }

        return "\(formatVideoTime(start)) - \(formatVideoTime(end))"
    }

    private func formatVideoTime(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct PetPalDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(
                LinearGradient(
                    colors: [PetPalTheme.danger, PetPalTheme.cocoa],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
