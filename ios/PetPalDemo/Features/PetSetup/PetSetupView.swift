import SwiftUI

struct PetSetupView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var petName = ""
    @State private var species = "cat"
    @State private var style = "tsundere"
    @State private var selectedVoiceKey = "cat-soft"
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let speciesOptions = [("cat", "猫咪"), ("dog", "狗狗")]
    private let styleOptions = [("tsundere", "傲娇"), ("loyal", "忠诚"), ("chatty", "话痨")]
    private let voicePresets = [
        "cat": [("cat-soft", "奶呼噜"), ("cat-princess", "小公主"), ("cat-night", "月光喵")],
        "dog": [("dog-sunny", "太阳尾巴"), ("dog-cocoa", "可可伙伴"), ("dog-bounce", "弹跳泡泡")],
    ]

    var body: some View {
        Form {
            Section("宠物基础信息") {
                TextField("宠物名字", text: $petName)
                    .accessibilityLabel("宠物名字输入框")

                Picker("种类", selection: $species) {
                    ForEach(speciesOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .onChange(of: species, initial: true) {
                    if let firstVoice = availableVoices.first?.0 {
                        selectedVoiceKey = firstVoice
                    }
                }

                Picker("说话风格", selection: $style) {
                    ForEach(styleOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }

                Picker("预设声音", selection: $selectedVoiceKey) {
                    ForEach(availableVoices, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
            }

            Section("创建宠物") {
                Button {
                    Task {
                        await createPet()
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("创建宠物")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(
                    isSubmitting ||
                    appStore.session.userId == nil ||
                    petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .buttonStyle(.borderedProminent)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Pet Create")
    }

    private var availableVoices: [(String, String)] {
        voicePresets[species] ?? []
    }

    private var selectedVoiceLabel: String {
        availableVoices.first(where: { $0.0 == selectedVoiceKey })?.1 ?? "奶呼噜"
    }

    private func createPet() async {
        guard let userID = appStore.session.userId else { return }

        let trimmedName = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        do {
            let response = try await appStore.apiClient.createPet(
                CreatePetRequest(
                    userID: userID,
                    name: trimmedName,
                    species: species,
                    languageStyle: style,
                    voiceType: "preset",
                    voiceKey: selectedVoiceKey,
                    voiceLabel: selectedVoiceLabel
                )
            )

            appStore.applyCreatedPet(
                response: response,
                name: trimmedName,
                species: species,
                style: style
            )
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }

        isSubmitting = false
    }
}
