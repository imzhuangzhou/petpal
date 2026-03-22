import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct PetSetupView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var currentStep = 0
    @State private var petName = ""
    @State private var species = "cat"
    @State private var style = "tsundere"
    @State private var voiceMode = "preset"
    @State private var selectedVoiceKey = "cat-soft"
    @State private var isSubmitting = false
    @State private var isRecording = false
    @State private var recordingSeconds = 0
    @State private var recordedAudioFileURL: URL?
    @State private var errorMessage: String?
    @State private var helperMessage: String?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingTimer: Timer?
    @State private var stopWorkItem: DispatchWorkItem?
    @State private var selectedReferencePhotoItem: PhotosPickerItem?
    @State private var referencePhotoLocalURL: URL?
    @State private var referencePhotoRemotePath = ""
    @State private var generatedAvatarRemotePath = ""
    @State private var avatarGenerationState: AvatarGenerationState = .idle
    @State private var avatarMessage: String?

    private let speciesOptions = [
        SpeciesOption(id: "cat", artAsset: .petCat, label: "喵星人", summary: "轻盈、敏感、会把心事藏在尾巴尖。", defaultVoiceKey: "cat-soft"),
        SpeciesOption(id: "dog", artAsset: .petDog, label: "汪星人", summary: "热情、黏人、会把开心都写在眼睛里。", defaultVoiceKey: "dog-sunny"),
    ]

    private let styleOptions = [
        StyleOption(id: "tsundere", artAsset: .styleTsundere, name: "傲娇主子", desc: "嘴上不说，心里却记得你什么时候回家。"),
        StyleOption(id: "loyal", artAsset: .styleLoyal, name: "忠诚小跟班", desc: "每一句回应都像摇着尾巴朝你跑来。"),
        StyleOption(id: "chatty", artAsset: .styleChatty, name: "碎碎念搭子", desc: "芝麻大的小事，也想马上讲给你听。"),
        StyleOption(id: "chill", artAsset: .styleChill, name: "松弛感主角", desc: "不慌不忙，连撒娇都带着午后阳光味。"),
    ]

    private let voicePresets = [
        "cat": [
            VoicePreset(id: "cat-soft", name: "奶呼噜", badge: "推荐", tone: "柔软", description: "轻轻黏人，像在耳边打呼噜。"),
            VoicePreset(id: "cat-princess", name: "小公主", badge: "人气", tone: "灵巧", description: "清脆娇气，适合高冷又精致的小猫。"),
            VoicePreset(id: "cat-night", name: "月光喵", badge: "治愈", tone: "低缓", description: "松弛慵懒，像半夜跳上床沿轻轻叫你。"),
        ],
        "dog": [
            VoicePreset(id: "dog-sunny", name: "太阳尾巴", badge: "推荐", tone: "热情", description: "明亮亲近，像一见到你就忍不住摇尾巴。"),
            VoicePreset(id: "dog-cocoa", name: "可可伙伴", badge: "治愈", tone: "温和", description: "暖暖的陪伴感，像会趴在脚边安静守着你。"),
            VoicePreset(id: "dog-bounce", name: "弹跳泡泡", badge: "人气", tone: "活力", description: "轻快弹跳，适合藏不住开心的小狗。"),
        ],
    ]

    var body: some View {
        PetPalShell {
            GeometryReader { geometry in
                let contentWidth = min(max(geometry.size.width - 40, 280), 520)
                let isCompactLayout = contentWidth < 360

                ZStack {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            PetPalStepIndicator(total: 3, current: currentStep)

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
                                    stepOneContent(contentWidth: contentWidth, isCompactLayout: isCompactLayout)
                                case 1:
                                    stepTwoContent(contentWidth: contentWidth, isCompactLayout: isCompactLayout)
                                default:
                                    stepThreeContent(contentWidth: contentWidth, isCompactLayout: isCompactLayout)
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
                        .padding(.bottom, currentStep == 0 ? 36 : 140)
                    }

                    if isSubmitting {
                        PetPalLoadingOverlay(
                            title: "正在建立宠物档案...",
                            subtitle: "我们会保存参考照片、人格和声音设定，接着进入演示视频上传。"
                        )
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if currentStep > 0 {
                bottomActionBar
            }
        }
        .onChange(of: selectedReferencePhotoItem) {
            Task {
                await importReferencePhoto()
            }
        }
        .onAppear {
            if let firstVoice = availableVoices.first?.id {
                selectedVoiceKey = firstVoice
            }
        }
        .onChange(of: species, initial: false) {
            if let firstVoice = availableVoices.first?.id {
                selectedVoiceKey = firstVoice
            }
        }
        .onDisappear {
            cleanupRecordingResources()
            cleanupReferencePhotoFile()
        }
    }

    private var selectedSpecies: SpeciesOption {
        speciesOptions.first(where: { $0.id == species }) ?? speciesOptions[0]
    }

    private var availableVoices: [VoicePreset] {
        voicePresets[species] ?? []
    }

    private var selectedVoiceLabel: String {
        availableVoices.first(where: { $0.id == selectedVoiceKey })?.name ?? "奶呼噜"
    }

    private var defaultVoiceKey: String {
        selectedSpecies.defaultVoiceKey
    }

    private var trimmedPetName: String {
        petName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        case 1:
            return "给它一点说话脾气"
        default:
            return "最后挑一个声音"
        }
    }

    private var heroSubtitle: String {
        switch currentStep {
        case 0:
            return "先上传它的参考照片，再补上名字和种类，我们会顺手生成一张可确认的卡通形象。"
        case 1:
            return "聊天人格可以跳过，默认会沿用现在这套傲娇又黏人的语气。"
        default:
            return "声音设定同样可以跳过，默认会自动带上该物种的推荐声线。"
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
            return "下一步，设置聊天人格"
        case 1:
            return "下一步，设置声音"
        default:
            return "完成建档，继续上传视频"
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
            HStack(alignment: .center, spacing: 12) {
                PetPalCapsuleLabel(text: "Pet setup", style: .hero)
                Spacer(minLength: 0)
                Text("先补名字和种类，再生成它的卡通形象。")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("名字")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)

                TextField("例如：发财、奶盖、奥利奥...", text: $petName)
                    .petPalTextFieldStyle()
                    .accessibilityLabel("宠物名字输入框")
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
    private func stepOneContent(contentWidth _: CGFloat, isCompactLayout: Bool) -> some View {
        PetSetupStepHeader(
            eyebrow: "基础信息",
            title: "先上传目标宠物照片，再填写它的基本资料",
            chipText: "Step 1"
        )

        stepOneArtworkCard(isCompactLayout: isCompactLayout)
    }

    @ViewBuilder
    private func stepTwoContent(contentWidth: CGFloat, isCompactLayout: Bool) -> some View {
        PetSetupStepHeader(
            eyebrow: "聊天人格",
            title: "它平时会怎么跟你说话？",
            chipText: "Step 2",
            onSkip: {
                skipStyleStep()
            }
        )

        Text("这一页可以跳过；如果不选，我们会沿用默认的“傲娇主子”风格。")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(PetPalTheme.inkSoft)
            .lineSpacing(3)

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
    private func stepThreeContent(contentWidth: CGFloat, isCompactLayout: Bool) -> some View {
        PetSetupStepHeader(
            eyebrow: "声音设定",
            title: "先选一个像它的声音，再决定要不要复刻真实原声",
            chipText: "Step 3",
            onSkip: {
                Task {
                    await skipVoiceStep()
                }
            }
        )

        Text("这一步也可以直接跳过，我们会默认给它带上 \(selectedVoiceLabel) 这条推荐声线。")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(PetPalTheme.inkSoft)
            .lineSpacing(3)

        LazyVGrid(columns: optionColumns(for: contentWidth), spacing: 12) {
            ForEach(availableVoices) { preset in
                VStack(spacing: 10) {
                    Button {
                        voiceMode = "preset"
                        selectedVoiceKey = preset.id
                        helperMessage = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                Text(preset.name)
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                    .foregroundStyle(PetPalTheme.ink)

                                Spacer(minLength: 6)

                                Text(preset.badge)
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(PetPalTheme.caramel)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "FFE8CF").opacity(0.95))
                                    .clipShape(Capsule())
                            }

                            Text(preset.tone)
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(Color(hex: "9E7760"))

                            Text(preset.description)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(PetPalTheme.inkSoft)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(tileFill(isSelected: voiceMode == "preset" && selectedVoiceKey == preset.id))
                        .overlay(tileBorder(isSelected: voiceMode == "preset" && selectedVoiceKey == preset.id))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button("试听一下") {
                        helperMessage = "iOS Demo 暂未接入预设声音试听，但会保留和 web 一致的声音配置。"
                    }
                    .buttonStyle(PetPalSecondaryButtonStyle())
                }
            }
        }

        PetPalSurfaceCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("复刻真实宠物声音")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(PetPalTheme.ink)

                        Spacer(minLength: 8)

                        PetPalCapsuleLabel(text: "可选", style: .soft)
                    }

                    Text("录 3-6 秒叫声、呼噜声或日常撒娇声，我们会把它保存成专属声音样本。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .lineSpacing(3)
                }
            }

            if let recordedAudioFileURL {
                Text("已录制文件：\(recordedAudioFileURL.lastPathComponent)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
            }

            HStack(spacing: 10) {
                Button(isRecording ? "停止录音" : "开始录音") {
                    if isRecording {
                        stopRecording()
                    } else {
                        Task {
                            await startRecording()
                        }
                    }
                }
                .buttonStyle(PetPalSecondaryButtonStyle())

                if recordingSeconds > 0 {
                    Text("\(recordingSeconds)s")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.caramel)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Color(hex: "E3F0E5").opacity(0.95))
                        .clipShape(Capsule())
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        voiceMode == "clone" || recordedAudioFileURL != nil
                            ? Color(hex: "EDA579")
                            : PetPalTheme.lineStrong,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            )

            if let helperMessage {
                Text(helperMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func stepOneArtworkCard(isCompactLayout: Bool) -> some View {
        let previewHeight = isCompactLayout ? 220.0 : 250.0

        PetPalSurfaceCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("参考照片与卡通形象")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)

                    Text(stepOneArtworkDescription)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .lineSpacing(3)
                }

                Spacer(minLength: 8)

                PetPalCapsuleLabel(text: "Step 1", style: .sticker)
            }

            switch avatarGenerationState {
            case .idle:
                PhotosPicker(
                    selection: $selectedReferencePhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    PetSetupAvatarPlaceholder(
                        title: "点击上传宠物照片",
                        subtitle: "通过系统相册选择 1 张正脸或特征清晰的照片，我们会直接开始生成卡通形象。",
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

            if let avatarMessage, !avatarMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(avatarMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(avatarGenerationState == .failed ? PetPalTheme.warning : PetPalTheme.inkSoft)
                    .lineSpacing(3)
            }

            switch avatarGenerationState {
            case .generated:
                if isCompactLayout {
                    VStack(spacing: 10) {
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
                            Text("更换参考照片")
                        }
                        .buttonStyle(PetPalSecondaryButtonStyle())

                        Button("保存信息，进入下一步") {
                            advanceFromStepOne()
                        }
                        .buttonStyle(PetPalPrimaryButtonStyle())
                        .disabled(!canContinueFromStepOne)
                    }
                } else {
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
                            Text("更换参考照片")
                        }
                        .buttonStyle(PetPalSecondaryButtonStyle())
                    }

                    Button("保存信息，进入下一步") {
                        advanceFromStepOne()
                    }
                    .buttonStyle(PetPalPrimaryButtonStyle())
                    .disabled(!canContinueFromStepOne)
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
                            Text("更换参考照片")
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
                            Text("更换参考照片")
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

    private var stepOneArtworkDescription: String {
        switch avatarGenerationState {
        case .idle:
            return "上传参考照片后会自动生成 1 张 1:1 的卡通形象，成功后就能保存信息进入下一步。"
        case .generating:
            return "正在根据参考照片生成卡通形象，请稍等片刻。"
        case .generated:
            return "如果觉得不像它，可以重新生成或更换参考照片。"
        case .failed:
            return "参考照片已经上传成功，你可以重试生成，或者换一张更清晰的照片。"
        }
    }

    private func handlePrimaryAction() {
        errorMessage = nil

        switch currentStep {
        case 0:
            advanceFromStepOne()
        case 1:
            withAnimation(.easeInOut(duration: 0.22)) {
                currentStep = 2
            }
        default:
            Task {
                await createPet()
            }
        }
    }

    private func skipStyleStep() {
        style = "tsundere"
        withAnimation(.easeInOut(duration: 0.22)) {
            currentStep = 2
        }
    }

    private func skipVoiceStep() async {
        voiceMode = "preset"
        selectedVoiceKey = defaultVoiceKey
        helperMessage = nil
        cleanupRecordingResources()
        cleanupRecordedAudioFile()
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
            avatarMessage = "参考照片已接收，正在生成卡通形象..."
            await generateAvatar(from: copiedURL)
        } catch {
            errorMessage = "导入参考照片失败：\(error.localizedDescription)"
        }
    }

    private func generateAvatar(from localURL: URL) async {
        avatarGenerationState = .generating
        avatarMessage = "正在根据这张照片生成卡通形象..."

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
                avatarMessage = "已生成卡通形象，可以保存信息进入下一步，也可以重新生成或更换照片。"
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

        guard let normalizedData = image.jpegData(compressionQuality: 0.92) else {
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

        if voiceMode == "clone", recordedAudioFileURL == nil {
            errorMessage = "请先录一段几秒钟的宠物声音。"
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
                voiceType: voiceMode == "clone" ? "clone" : "preset",
                voiceKey: voiceMode == "clone" ? "custom-clone" : selectedVoiceKey,
                voiceLabel: voiceMode == "clone" ? "\(trimmedPetName)原声" : selectedVoiceLabel
            )

            let response = try await appStore.apiClient.createPet(request)

            appStore.applyCreatedPet(
                response: response,
                name: trimmedPetName,
                species: species,
                style: style
            )

            if voiceMode == "clone", let recordedAudioFileURL {
                let uploadResponse = try await appStore.apiClient.uploadPetVoiceSample(
                    petID: response.id,
                    label: "\(trimmedPetName)原声",
                    audioFileURL: recordedAudioFileURL
                )
                appStore.applyUploadedVoiceSample(uploadResponse)
            }
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }

    private func startRecording() async {
        errorMessage = nil
        helperMessage = nil

        let permissionGranted = await requestRecordingPermission()
        guard permissionGranted else {
            errorMessage = "无法使用麦克风，请在系统设置里允许录音权限。"
            return
        }

        cleanupRecordingResources()
        cleanupRecordedAudioFile()

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)

            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]

            let recorder = try AVAudioRecorder(url: destinationURL, settings: settings)
            recorder.prepareToRecord()
            recorder.record()

            audioRecorder = recorder
            isRecording = true
            voiceMode = "clone"
            recordingSeconds = 0

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                recordingSeconds += 1
            }

            let workItem = DispatchWorkItem {
                stopRecording()
            }
            stopWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: workItem)
        } catch {
            errorMessage = "开始录音失败：\(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        guard let recorder = audioRecorder else { return }

        recorder.stop()
        recordedAudioFileURL = recorder.url
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        stopWorkItem?.cancel()
        stopWorkItem = nil
        audioRecorder = nil
        helperMessage = "原声样本已保存，创建宠物后会自动上传。"

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            helperMessage = "录音已结束，但音频会话关闭时出现小问题。"
        }
    }

    private func requestRecordingPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                switch AVAudioApplication.shared.recordPermission {
                case .granted:
                    continuation.resume(returning: true)
                case .denied:
                    continuation.resume(returning: false)
                case .undetermined:
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                @unknown default:
                    continuation.resume(returning: false)
                }
            } else {
                let audioSession = AVAudioSession.sharedInstance()

                switch audioSession.recordPermission {
                case .granted:
                    continuation.resume(returning: true)
                case .denied:
                    continuation.resume(returning: false)
                case .undetermined:
                    audioSession.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                @unknown default:
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func cleanupRecordingResources() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        stopWorkItem?.cancel()
        stopWorkItem = nil
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        recordingSeconds = 0
    }

    private func cleanupRecordedAudioFile() {
        guard let recordedAudioFileURL else { return }
        try? FileManager.default.removeItem(at: recordedAudioFileURL)
        self.recordedAudioFileURL = nil
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
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFF3E5"), Color(hex: "FFE2CC")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: height)
                .overlay(
                    VStack(spacing: 10) {
                        PetPalArtImage(asset: accentAsset)
                            .frame(width: 40, height: 40)

                        Text(title)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(PetPalTheme.ink)
                            .multilineTextAlignment(.center)

                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(PetPalTheme.inkSoft)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 20)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(PetPalTheme.lineStrong, style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
                )
        }
    }
}

private struct PetSetupArtworkPreview: View {
    let remoteImageURL: URL?
    let fallbackAsset: PetPalArtAsset
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(hex: "FFF5E9"))
            .frame(height: height)
            .overlay {
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(PetPalTheme.line.opacity(0.82), lineWidth: 1)
            )
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
                    colors: [Color(hex: "FFF3E8"), Color(hex: "FFE8DA")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: height)
            .overlay {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color(hex: "EF986A"))

                    Text("正在生成动漫卡通形象")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)

                    Text("生成期间页面会停留在当前步骤，完成后你可以重试、确认或放弃。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(PetPalTheme.inkSoft)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 18)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(hex: "EFC0A5"), lineWidth: 1.2)
            )
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
    let defaultVoiceKey: String
}

private struct StyleOption: Identifiable {
    let id: String
    let artAsset: PetPalArtAsset
    let name: String
    let desc: String
}

private struct VoicePreset: Identifiable {
    let id: String
    let name: String
    let badge: String
    let tone: String
    let description: String
}
