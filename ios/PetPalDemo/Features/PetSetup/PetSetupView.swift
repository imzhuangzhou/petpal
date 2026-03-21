import AVFoundation
import SwiftUI

struct PetSetupView: View {
    @EnvironmentObject private var appStore: AppStore
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

    private let twoColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private let speciesOptions = [
        SpeciesOption(id: "cat", emoji: "🐱", label: "喵星人", summary: "轻盈、敏感、会把心事藏在尾巴尖。", defaultVoiceKey: "cat-soft"),
        SpeciesOption(id: "dog", emoji: "🐶", label: "汪星人", summary: "热情、黏人、会把开心都写在眼睛里。", defaultVoiceKey: "dog-sunny"),
    ]

    private let styleOptions = [
        StyleOption(id: "tsundere", emoji: "😼", name: "傲娇主子", desc: "嘴上不说，心里却记得你什么时候回家。"),
        StyleOption(id: "loyal", emoji: "🐕", name: "忠诚小跟班", desc: "每一句回应都像摇着尾巴朝你跑来。"),
        StyleOption(id: "chatty", emoji: "🪽", name: "碎碎念搭子", desc: "芝麻大的小事，也想马上讲给你听。"),
        StyleOption(id: "chill", emoji: "🛋️", name: "松弛感主角", desc: "不慌不忙，连撒娇都带着午后阳光味。"),
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
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        PetPalStepIndicator(total: 2, current: 0)

                        PetPalHeroCard(
                            badge: "Pet setup",
                            stamp: selectedSpecies.emoji,
                            title: "认识一下新伙伴",
                            subtitle: "先定好它的种类、说话风格和声音，后面聊天时就会更像它本人。"
                        )

                        PetPalPanelCard {
                            PetPalSectionHeader(
                                eyebrow: "基础信息",
                                title: "它是家里的哪位小朋友？",
                                chipText: "Step 1"
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                Text("名字")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(PetPalTheme.inkSoft)

                                TextField("例如：发财、奶盖、奥利奥...", text: $petName)
                                    .petPalTextFieldStyle()
                                    .accessibilityLabel("宠物名字输入框")
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("宠物种类")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(PetPalTheme.inkSoft)

                                LazyVGrid(columns: twoColumns, spacing: 12) {
                                    ForEach(speciesOptions) { option in
                                        Button {
                                            species = option.id
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(option.emoji)
                                                    .font(.system(size: 28))

                                                Text(option.label)
                                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                                    .foregroundStyle(PetPalTheme.ink)

                                                Text(option.summary)
                                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                                    .foregroundStyle(PetPalTheme.inkSoft)
                                                    .multilineTextAlignment(.leading)
                                                    .lineSpacing(3)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(16)
                                            .background(tileFill(isSelected: species == option.id))
                                            .overlay(tileBorder(isSelected: species == option.id))
                                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        PetPalPanelCard {
                            PetPalSectionHeader(
                                eyebrow: "聊天人格",
                                title: "它平时会怎么跟你说话？",
                                chipText: "Step 2"
                            )

                            LazyVGrid(columns: twoColumns, spacing: 12) {
                                ForEach(styleOptions) { option in
                                    Button {
                                        style = option.id
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(option.emoji)
                                                .font(.system(size: 24))

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
                                        .background(tileFill(isSelected: style == option.id))
                                        .overlay(tileBorder(isSelected: style == option.id))
                                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        PetPalPanelCard {
                            PetPalSectionHeader(
                                eyebrow: "声音设定",
                                title: "先选一个像它的声音，再决定要不要复刻真实原声",
                                chipText: "Step 3"
                            )

                            LazyVGrid(columns: twoColumns, spacing: 12) {
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

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(PetPalTheme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 130)
                }

                if isSubmitting {
                    PetPalLoadingOverlay(
                        title: "正在建立宠物档案...",
                        subtitle: "我们会保存它的种类、人格和声音设定，接着进入今日上下文上传。"
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                Button {
                    Task {
                        await createPet()
                    }
                } label: {
                    Text("下一步，准备上传演示视频")
                }
                .buttonStyle(PetPalPrimaryButtonStyle())
                .disabled(
                    isSubmitting ||
                    appStore.session.userId == nil ||
                    petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
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

    private func createPet() async {
        guard let userID = appStore.session.userId else { return }

        let trimmedName = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if voiceMode == "clone", recordedAudioFileURL == nil {
            errorMessage = "请先录一段几秒钟的宠物声音。"
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            let request = CreatePetRequest(
                userID: userID,
                name: trimmedName,
                species: species,
                languageStyle: style,
                voiceType: voiceMode == "clone" ? "clone" : "preset",
                voiceKey: voiceMode == "clone" ? "custom-clone" : selectedVoiceKey,
                voiceLabel: voiceMode == "clone" ? "\(trimmedName)原声" : selectedVoiceLabel
            )

            let response = try await appStore.apiClient.createPet(request)

            appStore.applyCreatedPet(
                response: response,
                name: trimmedName,
                species: species,
                style: style
            )

            if voiceMode == "clone", let recordedAudioFileURL {
                let uploadResponse = try await appStore.apiClient.uploadPetVoiceSample(
                    petID: response.id,
                    label: "\(trimmedName)原声",
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

private struct SpeciesOption: Identifiable {
    let id: String
    let emoji: String
    let label: String
    let summary: String
    let defaultVoiceKey: String
}

private struct StyleOption: Identifiable {
    let id: String
    let emoji: String
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
