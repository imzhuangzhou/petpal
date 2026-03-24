import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechRecognizer: ObservableObject {
    struct CaptureResult: Sendable {
        let transcript: String
        let audioFileURL: URL?
        let durationSeconds: Int
    }

    @Published var transcript = ""
    @Published var isListening = false
    @Published var isAvailable = false
    @Published var errorMessage: String?

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStartedAt: Date?
    private var hasInstalledTap = false

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.isAvailable = recognizer?.isAvailable ?? false
    }

    func requestAuthorization() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let microphoneAuthorized = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        isAvailable = speechAuthorized && microphoneAuthorized && (recognizer?.isAvailable ?? false)
        if !speechAuthorized {
            errorMessage = "语音识别权限未授权"
        } else if !microphoneAuthorized {
            errorMessage = "无法使用麦克风，请在系统设置里允许录音权限。"
        } else if !(recognizer?.isAvailable ?? false) {
            errorMessage = "语音识别当前不可用"
        } else {
            errorMessage = nil
        }

        return isAvailable
    }

    func startListening() throws {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "语音识别不可用"
            throw CaptureError.unavailable
        }

        resetState(discardRecording: true)
        transcript = ""
        errorMessage = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "无法启动录音: \(error.localizedDescription)"
            throw error
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        do {
            recordingFile = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)
            recordingURL = fileURL
        } catch {
            errorMessage = "无法创建录音文件: \(error.localizedDescription)"
            throw error
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            request.append(buffer)
            do {
                try self.recordingFile?.write(from: buffer)
            } catch {
                Task { @MainActor in
                    self.errorMessage = "保存录音失败: \(error.localizedDescription)"
                }
            }
        }
        hasInstalledTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "无法启动音频引擎: \(error.localizedDescription)"
            resetState(discardRecording: true)
            throw error
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    self?.errorMessage = "语音识别中断: \(error.localizedDescription)"
                    _ = self?.stopListening()
                }
            }
        }

        recordingStartedAt = Date()
        isListening = true
    }

    @discardableResult
    func stopListening(discardRecording: Bool = false) -> CaptureResult {
        let result = CaptureResult(
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            audioFileURL: discardRecording ? nil : recordingURL,
            durationSeconds: captureDurationSeconds
        )

        resetState(discardRecording: discardRecording)
        return result
    }

    private var captureDurationSeconds: Int {
        guard let recordingStartedAt else { return 0 }
        let elapsed = Date().timeIntervalSince(recordingStartedAt)
        guard elapsed > 0 else { return 0 }
        return max(Int(elapsed.rounded(.up)), 1)
    }

    private func resetState(discardRecording: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recordingFile = nil

        if discardRecording, let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }

        self.recordingURL = nil
        self.recordingStartedAt = nil
        self.isListening = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            if errorMessage == nil {
                errorMessage = "录音结束，但音频会话关闭失败：\(error.localizedDescription)"
            }
        }
    }
}

extension SpeechRecognizer {
    enum CaptureError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "语音识别不可用"
            }
        }
    }
}
