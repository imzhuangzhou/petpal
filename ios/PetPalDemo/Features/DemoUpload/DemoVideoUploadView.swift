import AVFoundation
import SwiftUI
import UIKit

struct DemoVideoUploadView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var selectedCamera: MockCameraDevice?
    @State private var isRadarPresented = false
    @State private var isConnecting = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var connectionTask: Task<Void, Never>?
    @State private var radarSessionID = UUID()
    @State private var hasAttemptedCompletion = false

    var body: some View {
        PetPalShell {
            ScrollViewReader { scrollProxy in
                ZStack {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            PetPalPanelCard {
                                PetPalSectionHeader(
                                    eyebrow: "摄像头",
                                    title: "搜索并绑定摄像头",
                                    chipText: nil
                                )

                                Button {
                                    presentRadarScanner()
                                } label: {
                                    CameraBindingCard(
                                        camera: selectedCamera,
                                        isConnecting: isConnecting,
                                        showsValidationHighlight: cameraInlineFeedbackMessage != nil
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(selectedCamera == nil ? "添加摄像头" : "重新搜索摄像头")
                                .accessibilityHint("进入雷达扫描页，搜索附近的家庭摄像头")
                                .id(DemoUploadScrollTarget.cameraBinding.rawValue)

                                PetPalSurfaceCard {
                                    PetPalInfoRow(
                                        title: "当前设备",
                                        value: selectedCamera?.name ?? "暂未选择"
                                    )
                                    PetPalInfoRow(
                                        title: "连接状态",
                                        value: connectionStatusText
                                    )

                                    Text(selectedCamera == nil ? "点按上方卡片开始搜索。" : "点按上方卡片可重新搜索或切换设备。")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(PetPalTheme.inkSoft)
                                }

                                if let cameraInlineFeedbackMessage {
                                    PetPalInlineFeedback(message: cameraInlineFeedbackMessage, tone: .warning)
                                }

                                if let errorMessage {
                                    PetPalInlineFeedback(message: errorMessage, tone: .danger)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .safeAreaPadding(.top, 12)
                    .scrollBounceBehavior(.basedOnSize)

                    if isUploading {
                        PetPalLoadingOverlay(
                            title: "正在同步摄像头回放...",
                            subtitle: "我们会自动生成一段联调视频，并把它和摄像头名称一起上传。"
                        )
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack {
                        HStack(spacing: 10) {
                            Button("上一步") {
                                returnToPetStyleSelection()
                            }
                            .buttonStyle(PetPalSecondaryButtonStyle())
                            .frame(width: 118)
                            .disabled(isUploading)

                            Button {
                                Task {
                                    await completeConfiguration(scrollProxy: scrollProxy)
                                }
                            } label: {
                                Text("完成配置")
                            }
                            .buttonStyle(PetPalPrimaryButtonStyle())
                            .disabled(isUploading)
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
            }
        }
        .fullScreenCover(isPresented: $isRadarPresented) {
            CameraRadarScanView(
                cameras: MockCameraDevice.defaults,
                onSelect: beginBinding(camera:),
                onClose: { isRadarPresented = false }
            )
            .id(radarSessionID)
        }
        .onDisappear {
            connectionTask?.cancel()
        }
    }

    private var completionBlocker: DemoUploadCompletionBlocker? {
        if appStore.session.userId == nil || appStore.session.petId == nil {
            return .sessionUnavailable
        }

        if selectedCamera == nil {
            return .cameraMissing
        }

        if isConnecting {
            return .cameraConnecting
        }

        return nil
    }

    private var cameraInlineFeedbackMessage: String? {
        guard hasAttemptedCompletion else { return nil }
        return completionBlocker?.inlineMessage
    }

    private var connectionStatusText: String {
        if isUploading {
            return "正在同步视频"
        }

        if isConnecting {
            return "正在连接"
        }

        if selectedCamera != nil {
            return "已连接"
        }

        return "等待绑定"
    }

    private func presentRadarScanner() {
        errorMessage = nil
        radarSessionID = UUID()
        isRadarPresented = true
    }

    private func returnToPetStyleSelection() {
        connectionTask?.cancel()
        connectionTask = nil
        isConnecting = false
        isRadarPresented = false
        errorMessage = nil
        appStore.onboardingRoute = .petSetup(step: 1)
    }

    private func beginBinding(camera: MockCameraDevice) {
        errorMessage = nil
        connectionTask?.cancel()
        isRadarPresented = false
        selectedCamera = camera
        isConnecting = true

        connectionTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if selectedCamera?.id == camera.id {
                    isConnecting = false
                }
            }
        }
    }

    private func presentCompletionBlocker(_ blocker: DemoUploadCompletionBlocker, scrollProxy: ScrollViewProxy) {
        hasAttemptedCompletion = true
        PetPalHaptics.warning()

        withAnimation(.easeInOut(duration: 0.22)) {
            scrollProxy.scrollTo(DemoUploadScrollTarget.cameraBinding.rawValue, anchor: .center)
        }
    }

    private func completeConfiguration(scrollProxy: ScrollViewProxy) async {
        if let blocker = completionBlocker {
            presentCompletionBlocker(blocker, scrollProxy: scrollProxy)
            return
        }

        guard
            let userID = appStore.session.userId,
            let petID = appStore.session.petId,
            let selectedCamera,
            !isConnecting
        else {
            return
        }

        isUploading = true
        hasAttemptedCompletion = true
        errorMessage = nil

        var generatedVideoURL: URL?

        defer {
            isUploading = false

            if let generatedVideoURL {
                try? FileManager.default.removeItem(at: generatedVideoURL)
            }
        }

        do {
            let mockVideoURL = try await MockCameraVideoGenerator.generateVideo(cameraName: selectedCamera.name)
            generatedVideoURL = mockVideoURL

            let response = try await appStore.apiClient.uploadDemoVideo(
                DemoVideoUploadRequest(
                    userID: userID,
                    petID: petID,
                    cameraName: selectedCamera.name,
                    cameraID: appStore.session.cameraId,
                    videoFileURL: mockVideoURL
                )
            )

            appStore.applyUploadedDemoVideo(response)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "连接成功了，但联调视频上传失败，请再试一次。"
        }
    }
}

private enum DemoUploadScrollTarget: String {
    case cameraBinding
}

private enum DemoUploadCompletionBlocker {
    case sessionUnavailable
    case cameraMissing
    case cameraConnecting

    var inlineMessage: String {
        switch self {
        case .sessionUnavailable:
            return "请先完成宠物建档，再回来绑定摄像头。"
        case .cameraMissing:
            return "先搜索并绑定一个摄像头，才能完成当前配置。"
        case .cameraConnecting:
            return "摄像头还在连接中，连上后就能继续完成配置。"
        }
    }
}

private struct CameraBindingCard: View {
    let camera: MockCameraDevice?
    let isConnecting: Bool
    let showsValidationHighlight: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(cardBackground)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(cardBorder, lineWidth: 1.5)

            Group {
                if let camera {
                    boundCard(camera: camera)
                } else {
                    emptyCard
                }
            }
            .padding(18)
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .shadow(color: PetPalTheme.caramel.opacity(0.14), radius: 18, y: 10)
    }

    private var cardBackground: LinearGradient {
        if camera == nil {
            return LinearGradient(
                colors: [Color(hex: "FFF8EF"), Color(hex: "FFF0E2")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color(hex: "FFF5EC"), Color(hex: "FCEADA")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        if showsValidationHighlight {
            return PetPalTheme.danger.opacity(0.72)
        }

        return isConnecting ? Color(hex: "E8B48C") : PetPalTheme.lineStrong
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFE2C9"), Color(hex: "FFC89E")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 82, height: 82)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(.white)
                )
                .shadow(color: PetPalTheme.peach2.opacity(0.28), radius: 14, y: 8)

            Text("搜索并绑定摄像头")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(PetPalTheme.ink)

            Text("点击后即可搜索附近设备。")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(PetPalTheme.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func boundCard(camera: MockCameraDevice) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(camera.name)
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(PetPalTheme.ink)

                    Text(isConnecting ? "连接中" : "已连接")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isConnecting ? PetPalTheme.caramel : PetPalTheme.success)
                }

                Spacer(minLength: 10)

                PetPalCapsuleLabel(
                    text: isConnecting ? "连接中" : "已连接",
                    style: isConnecting ? .hero : .soft
                )
            }

            if isConnecting {
                CameraConnectingState(camera: camera)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MockCameraFeedView(camera: camera)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct CameraConnectingState: View {
    let camera: MockCameraDevice
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(camera.glowColor.opacity(0.2))
                    .frame(width: 110, height: 110)
                    .scaleEffect(isAnimating ? 1.08 : 0.92)

                Circle()
                    .stroke(camera.glowColor.opacity(0.26), lineWidth: 1.5)
                    .frame(width: 142, height: 142)
                    .scaleEffect(isAnimating ? 1.12 : 0.84)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, camera.coreColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .overlay(
                        Image(systemName: camera.icon)
                            .font(.system(size: 28, weight: .black))
                            .foregroundStyle(camera.iconColor)
                    )
            }

            VStack(spacing: 8) {
                Text("正在连接 \(camera.name)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
                    .multilineTextAlignment(.center)

                LoadingDots()

                Text("请稍等片刻，我们会自动完成连接。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

private struct LoadingDots: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color(hex: "D89167"))
                    .frame(width: 9, height: 9)
                    .offset(y: isAnimating ? -4 : 4)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

private struct MockCameraFeedView: View {
    let camera: MockCameraDevice

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { context in
            GeometryReader { proxy in
                let phase = animatedPhase(for: context.date)
                let size = proxy.size

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "7E6257"), Color(hex: "B59077")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Circle()
                        .fill(Color(hex: "F3D7B2").opacity(0.34))
                        .frame(width: size.width * 0.72, height: size.width * 0.72)
                        .offset(x: size.width * 0.38 + cos(phase * .pi * 2) * 8, y: -size.height * 0.12)
                        .blur(radius: 2)

                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "F3E5CF").opacity(0.9), Color(hex: "E6CBAE").opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size.width * 0.58, height: size.height * 0.42)
                        .offset(x: size.width * 0.1, y: size.height * 0.12)

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(hex: "B2886F").opacity(0.9))
                        .frame(width: size.width * 0.44, height: size.height * 0.16)
                        .offset(x: size.width * 0.13, y: size.height * 0.58)

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(hex: "8C695B").opacity(0.86))
                        .frame(width: size.width * 0.22, height: size.height * 0.18)
                        .offset(x: size.width * 0.62, y: size.height * 0.54)

                    Circle()
                        .fill(Color(hex: "4E403B").opacity(0.72))
                        .frame(width: size.width * 0.16, height: size.width * 0.16)
                        .offset(x: size.width * 0.66 + sin(phase * .pi * 2) * 10, y: size.height * 0.55)

                    Capsule()
                        .fill(Color(hex: "5A4A44").opacity(0.8))
                        .frame(width: size.width * 0.18, height: size.height * 0.09)
                        .offset(x: size.width * 0.58 + sin(phase * .pi * 2) * 10, y: size.height * 0.63)

                    ForEach(0..<10, id: \.self) { index in
                        Rectangle()
                            .fill(Color.white.opacity(index.isMultiple(of: 2) ? 0.035 : 0.018))
                            .frame(height: 2)
                            .offset(y: CGFloat(index) * (size.height / 10))
                    }

                    HStack(spacing: 8) {
                        PetPalCapsuleLabel(text: "LIVE", style: .hero)

                        Text(timeString(for: phase))
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Color.black.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .padding(14)

                    Text(camera.name)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.black.opacity(0.16))
                        .clipShape(Capsule())
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    private func animatedPhase(for date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
    }

    private func timeString(for phase: Double) -> String {
        let minute = Int(phase * 59)
        return String(format: "18:%02d", minute)
    }
}

private struct CameraRadarScanView: View {
    let cameras: [MockCameraDevice]
    let onSelect: (MockCameraDevice) -> Void
    let onClose: () -> Void

    @State private var discoveredCameraIDs: Set<String> = []
    @State private var isSweepAnimating = false
    @State private var isHaloExpanded = false

    var body: some View {
        PetPalShell(alignment: .center) {
            VStack(spacing: 20) {
                PetPalNavigationHeader(
                    title: "搜索附近摄像头",
                    onBack: onClose
                )
                .padding(.horizontal, 20)

                Text(scanStatusText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PetPalTheme.caramel)
                    .padding(.top, -8)

                radarPanel

                Text("点一下想绑定的设备，就会自动返回上一页。")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(PetPalTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)

                Spacer(minLength: 20)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 5.2).repeatForever(autoreverses: false)) {
                isSweepAnimating = true
            }

            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                isHaloExpanded = true
            }
        }
        .task {
            await runDiscoverySequence()
        }
    }

    private var scanStatusText: String {
        switch discoveredCameraIDs.count {
        case 0:
            return "雷达启动中"
        case 1:
            return "已发现 1 台设备"
        default:
            return "已发现 \(discoveredCameraIDs.count) 台设备"
        }
    }

    private var radarPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFF8EF").opacity(0.96), Color(hex: "FCEBD9").opacity(0.98)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(PetPalTheme.line.opacity(0.9), lineWidth: 1)
                )

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let radarSize = side - 36

                ZStack {
                    Circle()
                        .fill(Color(hex: "FFF1DF").opacity(0.85))
                        .frame(width: radarSize, height: radarSize)
                        .scaleEffect(isHaloExpanded ? 1.02 : 0.96)

                    Circle()
                        .stroke(Color(hex: "E7C9AC").opacity(0.72), lineWidth: 1)
                        .frame(width: radarSize, height: radarSize)

                    Circle()
                        .stroke(Color(hex: "E7C9AC").opacity(0.62), lineWidth: 1)
                        .frame(width: radarSize * 0.72, height: radarSize * 0.72)

                    Circle()
                        .stroke(Color(hex: "E7C9AC").opacity(0.5), lineWidth: 1)
                        .frame(width: radarSize * 0.42, height: radarSize * 0.42)

                    Rectangle()
                        .fill(Color(hex: "E7C9AC").opacity(0.38))
                        .frame(width: 1, height: radarSize)

                    Rectangle()
                        .fill(Color(hex: "E7C9AC").opacity(0.38))
                        .frame(width: radarSize, height: 1)

                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [
                                    Color.clear,
                                    Color(hex: "F8C79F").opacity(0.0),
                                    Color(hex: "F2B181").opacity(0.46),
                                    Color(hex: "F8D5B7").opacity(0.16),
                                    Color.clear
                                ],
                                center: .center
                            )
                        )
                        .frame(width: radarSize, height: radarSize)
                        .rotationEffect(.degrees(isSweepAnimating ? 360 : 0))

                    ForEach(cameras) { camera in
                        if discoveredCameraIDs.contains(camera.id) {
                            CameraRadarNode(camera: camera) {
                                onSelect(camera)
                            }
                            .position(
                                x: radarSize * camera.position.x + (proxy.size.width - radarSize) / 2,
                                y: radarSize * camera.position.y + (proxy.size.height - radarSize) / 2
                            )
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 20)
        .shadow(color: PetPalTheme.caramel.opacity(0.14), radius: 18, y: 10)
    }

    private func runDiscoverySequence() async {
        discoveredCameraIDs = []

        guard !cameras.isEmpty else { return }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        reveal(camera: cameras[0])

        guard cameras.count > 1 else { return }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        reveal(camera: cameras[1])
    }

    @MainActor
    private func reveal(camera: MockCameraDevice) {
        _ = withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            discoveredCameraIDs.insert(camera.id)
        }
    }
}

private struct CameraRadarNode: View {
    let camera: MockCameraDevice
    let action: () -> Void

    @State private var isRippling = false

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(camera.glowColor.opacity(0.24), lineWidth: 1.5)
                            .frame(width: 64, height: 64)
                            .scaleEffect(isRippling ? 1.8 : 0.72)
                            .opacity(isRippling ? 0 : 1)
                            .animation(
                                .easeOut(duration: 2.4)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.42),
                                value: isRippling
                            )
                    }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, camera.coreColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: camera.icon)
                                .font(.system(size: 22, weight: .black))
                                .foregroundStyle(camera.iconColor)
                        )
                        .shadow(color: camera.glowColor.opacity(0.28), radius: 10, y: 6)
                }

                Text(camera.name)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(PetPalTheme.ink)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            isRippling = true
        }
    }
}

private struct MockCameraDevice: Identifiable, Equatable {
    struct RadarPosition: Equatable {
        let x: CGFloat
        let y: CGFloat
    }

    let id: String
    let name: String
    let icon: String
    let coreColor: Color
    let glowColor: Color
    let iconColor: Color
    let position: RadarPosition

    static let defaults: [MockCameraDevice] = [
        MockCameraDevice(
            id: "ezviz-living-room",
            name: "萤石客厅",
            icon: "video.fill",
            coreColor: Color(hex: "FFD4B3"),
            glowColor: Color(hex: "F4B180"),
            iconColor: Color(hex: "7B5343"),
            position: RadarPosition(x: 0.34, y: 0.32)
        ),
        MockCameraDevice(
            id: "ezviz-bedroom",
            name: "萤石卧室",
            icon: "video.fill",
            coreColor: Color(hex: "FFE2CE"),
            glowColor: Color(hex: "E7B798"),
            iconColor: Color(hex: "7B5343"),
            position: RadarPosition(x: 0.7, y: 0.64)
        )
    ]
}

private enum MockCameraVideoGenerator {
    private enum GenerationError: LocalizedError {
        case cannotAddInput
        case cannotStartWriting
        case noPixelBufferPool
        case pixelBufferCreationFailed
        case contextCreationFailed
        case frameAppendFailed

        var errorDescription: String? {
            switch self {
            case .cannotAddInput:
                return "无法创建视频写入通道。"
            case .cannotStartWriting:
                return "无法开始生成联调视频。"
            case .noPixelBufferPool:
                return "视频缓冲区初始化失败。"
            case .pixelBufferCreationFailed:
                return "视频帧缓存创建失败。"
            case .contextCreationFailed:
                return "视频绘制上下文创建失败。"
            case .frameAppendFailed:
                return "联调视频帧写入失败。"
            }
        }
    }

    static func generateVideo(cameraName: String) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try buildVideo(cameraName: cameraName)
        }
        .value
    }

    private static func buildVideo(cameraName: String) throws -> URL {
        let frameRate = 12
        let durationSeconds = 4
        let totalFrames = frameRate * durationSeconds
        let size = CGSize(width: 960, height: 720)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("petpal-mock-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(input) else {
            throw GenerationError.cannotAddInput
        }

        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? GenerationError.cannotStartWriting
        }

        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else {
            throw GenerationError.noPixelBufferPool
        }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        for frame in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                usleep(1_000)
            }

            let progress = Double(frame) / Double(max(totalFrames - 1, 1))
            let image = drawFrame(cameraName: cameraName, progress: progress, size: size)
            let pixelBuffer = try makePixelBuffer(from: image, size: size, pool: pool)
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frame))

            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? GenerationError.frameAppendFailed
            }
        }

        input.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        if let error = writer.error {
            throw error
        }

        return outputURL
    }

    private static func makePixelBuffer(
        from image: CGImage,
        size: CGSize,
        pool: CVPixelBufferPool
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)

        guard let pixelBuffer else {
            throw GenerationError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw GenerationError.pixelBufferCreationFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: baseAddress,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw GenerationError.contextCreationFailed
        }

        context.draw(image, in: CGRect(origin: .zero, size: size))
        return pixelBuffer
    }

    private static func drawFrame(cameraName: String, progress: Double, size: CGSize) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { rendererContext in
            let context = rendererContext.cgContext

            let backgroundColors = [UIColor(hex: "6F564D").cgColor, UIColor(hex: "AE8A74").cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: backgroundColors, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])

            let glowCenter = CGPoint(
                x: size.width * 0.72 + cos(progress * .pi * 2) * 14,
                y: size.height * 0.18
            )
            let glowColors = [UIColor(hex: "F4D8B4").withAlphaComponent(0.42).cgColor, UIColor.clear.cgColor] as CFArray
            let glowGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0, 1])!
            context.drawRadialGradient(
                glowGradient,
                startCenter: glowCenter,
                startRadius: 6,
                endCenter: glowCenter,
                endRadius: size.width * 0.38,
                options: []
            )

            fillRoundedRect(
                in: CGRect(x: size.width * 0.1, y: size.height * 0.14, width: size.width * 0.56, height: size.height * 0.38),
                color: UIColor(hex: "F1DFC8"),
                radius: 34,
                context: context
            )

            fillRoundedRect(
                in: CGRect(x: size.width * 0.12, y: size.height * 0.58, width: size.width * 0.5, height: size.height * 0.16),
                color: UIColor(hex: "B1856B"),
                radius: 26,
                context: context
            )

            fillRoundedRect(
                in: CGRect(x: size.width * 0.62, y: size.height * 0.54, width: size.width * 0.18, height: size.height * 0.18),
                color: UIColor(hex: "8D6B5D"),
                radius: 22,
                context: context
            )

            let petX = size.width * 0.66 + sin(progress * .pi * 2) * 18
            context.setFillColor(UIColor(hex: "4A3D37").withAlphaComponent(0.78).cgColor)
            context.fillEllipse(in: CGRect(x: petX, y: size.height * 0.57, width: size.width * 0.16, height: size.height * 0.16))
            fillRoundedRect(
                in: CGRect(x: petX - size.width * 0.04, y: size.height * 0.66, width: size.width * 0.2, height: size.height * 0.08),
                color: UIColor(hex: "564843").withAlphaComponent(0.84),
                radius: 18,
                context: context
            )

            for index in 0..<12 {
                let y = CGFloat(index) * (size.height / 12)
                context.setFillColor(UIColor.white.withAlphaComponent(index.isMultiple(of: 2) ? 0.03 : 0.015).cgColor)
                context.fill(CGRect(x: 0, y: y, width: size.width, height: 2))
            }

            let badgeRect = CGRect(x: 28, y: 28, width: 110, height: 42)
            fillRoundedRect(
                in: badgeRect,
                color: UIColor(hex: "FFDAB8").withAlphaComponent(0.94),
                radius: 20,
                context: context
            )
            drawText(
                "LIVE",
                in: badgeRect.insetBy(dx: 18, dy: 10),
                font: .systemFont(ofSize: 20, weight: .black),
                color: UIColor(hex: "9D6348")
            )

            let timeRect = CGRect(x: 152, y: 28, width: 124, height: 42)
            fillRoundedRect(
                in: timeRect,
                color: UIColor.black.withAlphaComponent(0.16),
                radius: 20,
                context: context
            )
            let time = String(format: "18:%02d", Int(progress * 59))
            drawText(
                time,
                in: timeRect.insetBy(dx: 18, dy: 10),
                font: .systemFont(ofSize: 20, weight: .black),
                color: .white
            )

            let cameraRect = CGRect(x: 28, y: size.height - 68, width: 220, height: 38)
            fillRoundedRect(
                in: cameraRect,
                color: UIColor.black.withAlphaComponent(0.16),
                radius: 19,
                context: context
            )
            drawText(
                cameraName,
                in: cameraRect.insetBy(dx: 16, dy: 10),
                font: .systemFont(ofSize: 18, weight: .black),
                color: .white
            )
        }
        .cgImage!
    }

    private static func fillRoundedRect(
        in rect: CGRect,
        color: UIColor,
        radius: CGFloat,
        context: CGContext
    ) {
        context.saveGState()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        color.setFill()
        path.fill()
        context.restoreGState()
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
