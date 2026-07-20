import CoreLocation
import MapKit
import OutboundSalesCore
import SwiftUI

#if os(iOS)
import AVFoundation
import Speech
import UIKit
#endif

struct CustomerVisitPromptSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    @State private var isSavingQuickVisit = false
    @State private var message = ""
    @State private var showingDetailOptions = false
    @State private var showingTextMemo = false
    @State private var showingPhotoMemo = false
    @State private var showingVoiceMemo = false
    private let visitLocationService = VisitLocationService()

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name.isEmpty ? "방문" : customer.name) {
                    Text("상세한 히스토리를 기록하겠습니까?")
                        .font(.headline)
                    Text("아니요를 선택하면 현재 시간과 위치 주소만 빠르게 저장합니다. 예를 선택하면 텍스트 메모, 사진 메모, 음성 메모 중 하나를 남길 수 있습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isSavingQuickVisit {
                    Section {
                        ProgressView("방문 위치를 확인하는 중...")
                    }
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("방문")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("예") { showingDetailOptions = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("아니요") {
                        Task { await saveQuickVisit() }
                    }
                    .disabled(isSavingQuickVisit)
                }
            }
            .confirmationDialog("방문 메모 선택", isPresented: $showingDetailOptions, titleVisibility: .visible) {
                Button("텍스트 메모") { showingTextMemo = true }
                Button("사진 메모") { showingPhotoMemo = true }
                Button("음성 메모") { showingVoiceMemo = true }
                Button("취소", role: .cancel) {}
            }
            .sheet(isPresented: $showingTextMemo) {
                VisitTextMemoSheet(customer: customer) {
                    dismiss()
                }
                .environmentObject(state)
            }
            .sheet(isPresented: $showingPhotoMemo) {
                CustomerPhotoCaptureSheet(customer: customer, title: "사진 메모", visitKind: .photoMemo) {
                    dismiss()
                }
                .environmentObject(state)
            }
            #if os(iOS)
            .sheet(isPresented: $showingVoiceMemo) {
                VisitVoiceMemoSheet(customer: customer) {
                    dismiss()
                }
                .environmentObject(state)
            }
            #endif
        }
    }

    private func saveQuickVisit() async {
        isSavingQuickVisit = true
        defer { isSavingQuickVisit = false }

        do {
            let place = try await visitLocationService.currentVisitPlace()
            _ = state.addVisitHistory(
                customer: customer,
                kind: .quickLocation,
                locationAddress: place.address,
                mapSnapshotData: place.mapSnapshotData
            )
            dismiss()
        } catch {
            _ = state.addVisitHistory(customer: customer, kind: .quickLocation)
            message = "위치 없이 방문 시간을 저장했습니다."
            dismiss()
        }
    }
}

struct VisitTextMemoSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    let onSaved: () -> Void
    @State private var memo = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name.isEmpty ? "텍스트 메모" : customer.name) {
                    TextField("메모", text: $memo, axis: .vertical)
                        .lineLimit(5...10)
                }
            }
            .navigationTitle("텍스트 메모")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        _ = state.addVisitHistory(customer: customer, kind: .textMemo, memo: memo)
                        dismiss()
                        onSaved()
                    }
                    .disabled(memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

enum VisitMemoPreviewKind {
    case text
    case voice
}

struct VisitMemoPreviewRow: View {
    let log: VisitLog
    let kind: VisitMemoPreviewKind

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconName)
                .font(.title3.weight(.bold))
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(previewText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(log.visitedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if kind == .voice {
                Text(transcriptionStatusText)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var iconName: String {
        kind == .voice ? "waveform" : "text.bubble"
    }

    private var iconColor: Color {
        kind == .voice ? .purple : .blue
    }

    private var previewText: String {
        switch kind {
        case .text:
            return log.memo?.nilIfEmpty ?? "텍스트 메모"
        case .voice:
            return log.audioTranscript?.nilIfEmpty ?? transcriptionStatusText
        }
    }

    private var transcriptionStatusText: String {
        switch log.transcriptionStatus {
        case .pending:
            return "전사 대기중"
        case .transcribing:
            return "전사중"
        case .completed:
            return "전사 완료"
        case .failed:
            return "전사 실패"
        case .none:
            return "음성"
        }
    }
}

struct TextMemoDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let log: VisitLog

    var body: some View {
        NavigationStack {
            List {
                Section("기록") {
                    Text(log.memo?.nilIfEmpty ?? "내용 없음")
                        .font(.body)
                        .textSelection(.enabled)
                    LabeledContent("기록 시간", value: log.visitedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .navigationTitle("텍스트 메모")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

#if os(iOS)
struct VoiceMemoDetailSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let log: VisitLog
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var activeSegmentId: String?
    @State private var currentTime: TimeInterval = 0
    @State private var message = ""

    var body: some View {
        NavigationStack {
            List {
                Section("음성") {
                    Button {
                        togglePlayback()
                    } label: {
                        VoiceMemoControlButton(
                            title: isPlaying ? "일시정지" : "재생",
                            systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill",
                            color: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(currentLog.audioFileName == nil)

                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { currentTime },
                                set: { seek(to: $0) }
                            ),
                            in: 0...max(playbackDuration, 1)
                        )
                        HStack {
                            Text(Self.durationText(currentTime))
                            Spacer()
                            Text(Self.durationText(playbackDuration))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .disabled(currentLog.audioFileName == nil)

                    if let duration = currentLog.audioDuration {
                        LabeledContent("녹음 시간", value: Self.durationText(duration))
                    }
                    LabeledContent("기록 시간", value: currentLog.visitedAt.formatted(date: .abbreviated, time: .shortened))
                }

                Section("전사") {
                    if let segments = currentLog.audioSegments, !segments.isEmpty {
                        VoiceTranscriptText(
                            segments: segments,
                            activeSegmentId: activeSegmentId,
                            onTapSegment: playSegment
                        )
                    } else {
                        Text(currentLog.audioTranscript?.nilIfEmpty ?? transcriptionStatusText)
                            .textSelection(.enabled)
                            .foregroundStyle(currentLog.audioTranscript == nil ? .secondary : .primary)
                    }

                    if currentLog.audioFileName != nil && (currentLog.audioSegments?.isEmpty ?? true) {
                        Text(segmentFallbackText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("음성 메모")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") {
                        stopPlayback()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                stopPlayback()
            }
            .onAppear {
                requestSegmentTranscriptionIfNeeded()
            }
            .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
                guard isPlaying, let audioPlayer else { return }
                currentTime = audioPlayer.currentTime
                activeSegmentId = activeSegmentId(at: currentTime)
                if !audioPlayer.isPlaying {
                    isPlaying = false
                    activeSegmentId = nil
                }
            }
        }
    }

    private var currentLog: VisitLog {
        state.visitLogs.first(where: { $0.id == log.id }) ?? log
    }

    private var playbackDuration: TimeInterval {
        audioPlayer?.duration ?? currentLog.audioDuration ?? 0
    }

    private var transcriptionStatusText: String {
        switch currentLog.transcriptionStatus {
        case .pending:
            return "전사 대기중입니다."
        case .transcribing:
            return "전사중입니다."
        case .completed:
            return "전사된 내용이 없습니다."
        case .failed:
            return "전사에 실패했습니다. 음성은 재생할 수 있습니다."
        case .none:
            return "전사 정보가 없습니다."
        }
    }

    private var segmentFallbackText: String {
        switch currentLog.transcriptionStatus {
        case .transcribing:
            return "전사 구간을 생성하는 중입니다. 잠시 후 다시 표시됩니다."
        case .failed:
            return "전사 구간을 만들지 못했습니다. 음성은 슬라이더로 탐색할 수 있습니다."
        case .completed:
            return "이전 녹음에는 구간 정보가 없습니다. 새 녹음부터 구간 재생이 자동으로 생성됩니다."
        default:
            return "전사가 끝나면 구간별 재생 버튼이 표시됩니다."
        }
    }

    private func requestSegmentTranscriptionIfNeeded() {
        guard currentLog.audioFileName != nil,
              currentLog.audioSegments?.isEmpty != false,
              currentLog.transcriptionStatus != .transcribing else {
            return
        }
        state.transcribeVoiceMemoIfNeeded(logId: currentLog.id)
    }

    private func playSegment(_ segment: VoiceTranscriptionSegment) {
        do {
            try preparePlayerIfNeeded()
            audioPlayer?.currentTime = max(0, segment.timestamp)
            currentTime = max(0, segment.timestamp)
            activeSegmentId = segment.id
            audioPlayer?.play()
            isPlaying = true
        } catch {
            message = "선택한 구간을 재생하지 못했습니다."
            isPlaying = false
        }
    }

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            return
        }

        do {
            try preparePlayerIfNeeded()
            audioPlayer?.play()
            isPlaying = true
        } catch {
            message = "음성 메모를 재생하지 못했습니다."
            isPlaying = false
        }
    }

    private func preparePlayerIfNeeded() throws {
        guard audioPlayer == nil else { return }
        guard let fileName = currentLog.audioFileName else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        let player = try AVAudioPlayer(contentsOf: state.assetURL(fileName: fileName))
        player.prepareToPlay()
        player.currentTime = currentTime
        audioPlayer = player
    }

    private func seek(to time: TimeInterval) {
        currentTime = min(max(time, 0), max(playbackDuration, 0))
        audioPlayer?.currentTime = currentTime
        activeSegmentId = activeSegmentId(at: currentTime)
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        activeSegmentId = nil
    }

    private func activeSegmentId(at time: TimeInterval) -> String? {
        guard let segments = currentLog.audioSegments, !segments.isEmpty else { return nil }
        for index in segments.indices {
            let segment = segments[index]
            let nextStart = index < segments.index(before: segments.endIndex) ? segments[segments.index(after: index)].timestamp : playbackDuration
            let segmentEnd = max(segment.timestamp + max(segment.duration, 0.25), nextStart)
            if time >= segment.timestamp && time < segmentEnd {
                return segment.id
            }
        }
        return nil
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct VoiceTranscriptText: View {
    let segments: [VoiceTranscriptionSegment]
    let activeSegmentId: String?
    let onTapSegment: (VoiceTranscriptionSegment) -> Void

    var body: some View {
        TranscriptTextView(
            segments: segments,
            activeSegmentId: activeSegmentId,
            onTapSegment: onTapSegment
        )
        .frame(minHeight: 48)
    }
}

private struct TranscriptTextView: UIViewRepresentable {
    let segments: [VoiceTranscriptionSegment]
    let activeSegmentId: String?
    let onTapSegment: (VoiceTranscriptionSegment) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapSegment: onTapSegment)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        textView.addGestureRecognizer(tap)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.segments = segments
        let rendered = Self.renderedTranscript(segments: segments, activeSegmentId: activeSegmentId)
        context.coordinator.ranges = rendered.ranges
        textView.attributedText = rendered.text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 64
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    private static func renderedTranscript(
        segments: [VoiceTranscriptionSegment],
        activeSegmentId: String?
    ) -> (text: NSAttributedString, ranges: [NSRange]) {
        let output = NSMutableAttributedString()
        var ranges: [NSRange] = []
        for segment in segments {
            if !output.string.isEmpty {
                output.append(NSAttributedString(string: " "))
            }
            let start = output.length
            let isActive = segment.id == activeSegmentId
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: isActive ? UIColor.white : UIColor.label,
                .backgroundColor: isActive ? UIColor.systemBlue : UIColor.clear
            ]
            output.append(NSAttributedString(string: segment.text, attributes: attributes))
            ranges.append(NSRange(location: start, length: output.length - start))
        }
        return (output, ranges)
    }

    final class Coordinator: NSObject {
        var segments: [VoiceTranscriptionSegment] = []
        var ranges: [NSRange] = []
        let onTapSegment: (VoiceTranscriptionSegment) -> Void

        init(onTapSegment: @escaping (VoiceTranscriptionSegment) -> Void) {
            self.onTapSegment = onTapSegment
        }

        @MainActor @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView else { return }
            let location = recognizer.location(in: textView)
            let textContainer = textView.textContainer
            let layoutManager = textView.layoutManager
            var adjustedLocation = location
            adjustedLocation.x -= textView.textContainerInset.left
            adjustedLocation.y -= textView.textContainerInset.top
            let characterIndex = layoutManager.characterIndex(
                for: adjustedLocation,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            guard let index = ranges.firstIndex(where: { NSLocationInRange(characterIndex, $0) }),
                  segments.indices.contains(index) else {
                return
            }
            onTapSegment(segments[index])
        }
    }
}

private struct VoiceMemoControlButton: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .frame(width: 24)
            Text(title)
                .font(.headline.weight(.bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
#else
struct VoiceMemoDetailSheet: View {
    let log: VisitLog

    var body: some View {
        Text(log.audioTranscript ?? "음성 메모는 iPhone에서 재생할 수 있습니다.")
    }
}
#endif

#if os(iOS)
struct VisitVoiceMemoSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    let onSaved: () -> Void
    @StateObject private var recorder = VoiceMemoRecorder()
    @State private var selectedVoiceMemo: VisitLog?
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name.isEmpty ? "음성 메모" : customer.name) {
                    Text(recorder.statusText)
                        .foregroundStyle(recorder.isRecording ? .red : .secondary)
                    if recorder.duration > 0 {
                        LabeledContent("녹음 시간", value: Self.durationText(recorder.duration))
                    }
                }

                Section {
                    Button {
                        Task { await toggleRecordingPause() }
                    } label: {
                        VoiceMemoControlButton(
                            title: recorder.primaryActionTitle,
                            systemImage: recorder.primaryActionIcon,
                            color: recorder.primaryActionColor
                        )
                    }
                    .buttonStyle(.plain)

                    if recorder.isRecording || recorder.isPaused {
                        Button {
                            recorder.stop()
                        } label: {
                            VoiceMemoControlButton(
                                title: "녹음 종료",
                                systemImage: "stop.circle.fill",
                                color: .red
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        saveVoiceMemo()
                    } label: {
                        VoiceMemoControlButton(
                            title: "저장",
                            systemImage: "tray.and.arrow.down.fill",
                            color: .green
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(recorder.isRecording || recorder.isPaused || recorder.recordedURL == nil)
                    .opacity(recorder.isRecording || recorder.isPaused || recorder.recordedURL == nil ? 0.45 : 1)
                }

                if !recorder.interruptionMessage.isEmpty {
                    Section {
                        Text(recorder.interruptionMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !recentVoiceMemos.isEmpty {
                    Section("최근 음성 메모") {
                        ForEach(recentVoiceMemos.prefix(8)) { log in
                            Button {
                                selectedVoiceMemo = log
                            } label: {
                                VisitMemoPreviewRow(log: log, kind: .voice)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $selectedVoiceMemo) { log in
                VoiceMemoDetailSheet(log: log)
                    .environmentObject(state)
            }
            .navigationTitle("음성 메모")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private var recentVoiceMemos: [VisitLog] {
        state.visitLogs
            .filter { $0.customerId == customer.id && $0.kind == .voiceMemo }
            .sorted { $0.visitedAt > $1.visitedAt }
    }

    private func toggleRecordingPause() async {
        do {
            if recorder.isRecording {
                recorder.pause()
            } else if recorder.isPaused {
                try recorder.resume()
            } else {
                try await recorder.start()
            }
        } catch {
            message = "마이크 권한 또는 녹음 설정을 확인하세요."
        }
    }

    private func saveVoiceMemo() {
        guard let url = recorder.recordedURL else { return }
        do {
            let data = try Data(contentsOf: url)
            _ = state.addVisitHistory(
                customer: customer,
                kind: .voiceMemo,
                audioData: data,
                audioDuration: recorder.duration
            )
            dismiss()
            onSaved()
        } catch {
            message = "음성 메모를 저장하지 못했습니다."
        }
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

@MainActor
final class VoiceMemoRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordedURL: URL?
    @Published var duration: TimeInterval = 0
    @Published var interruptionMessage = ""
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var durationTimer: Timer?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var statusText: String {
        if isRecording {
            return "녹음 중입니다. 필요하면 일시정지할 수 있습니다."
        }
        if isPaused {
            return "녹음이 일시정지되었습니다. 다시 녹음하거나 종료하세요."
        }
        if recordedURL != nil {
            return "녹음이 준비되었습니다. 저장하면 고객 히스토리에 남습니다."
        }
        return "녹음 버튼을 눌러 음성 메모를 남기세요."
    }

    var primaryActionTitle: String {
        if isRecording { return "일시정지" }
        if isPaused { return "다시 녹음" }
        return "녹음 시작"
    }

    var primaryActionIcon: String {
        if isRecording { return "pause.circle.fill" }
        if isPaused { return "mic.circle.fill" }
        return "mic.circle.fill"
    }

    var primaryActionColor: Color {
        if isRecording { return .orange }
        if isPaused { return .blue }
        return .blue
    }

    func start() async throws {
        if #available(iOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else { throw VoiceMemoError.permissionDenied }
        } else {
            let granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else { throw VoiceMemoError.permissionDenied }
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.record()
        self.recorder = recorder
        self.recordedURL = url
        self.startedAt = Date()
        self.accumulatedDuration = 0
        self.duration = 0
        self.isRecording = true
        self.isPaused = false
        self.interruptionMessage = ""
        startTimer()
    }

    func pause() {
        guard isRecording else { return }
        updateDuration()
        accumulatedDuration = duration
        recorder?.pause()
        isRecording = false
        isPaused = true
        startedAt = nil
        stopTimer()
    }

    func resume() throws {
        guard isPaused, let recorder else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        recorder.record()
        startedAt = Date()
        isRecording = true
        isPaused = false
        interruptionMessage = ""
        startTimer()
    }

    func stop() {
        updateDuration()
        recorder?.stop()
        isRecording = false
        isPaused = false
        startedAt = nil
        stopTimer()
    }

    func cancel() {
        if isRecording || isPaused {
            stop()
        }
    }

    private func startTimer() {
        stopTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDuration()
            }
        }
    }

    private func stopTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateDuration() {
        if let startedAt {
            duration = accumulatedDuration + Date().timeIntervalSince(startedAt)
        } else {
            duration = accumulatedDuration
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            if isRecording {
                updateDuration()
                accumulatedDuration = duration
                recorder?.pause()
                isRecording = false
                isPaused = true
                startedAt = nil
                stopTimer()
                interruptionMessage = "전화 또는 다른 오디오로 녹음이 일시정지되었습니다. 통화가 끝나면 다시 녹음을 눌러 이어서 기록하세요."
            }
        case .ended:
            break
        @unknown default:
            break
        }
    }
}

private enum VoiceMemoError: Error {
    case permissionDenied
}
#endif

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

@MainActor
final class VisitLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func currentVisitPlace() async throws -> VisitPlace {
        let location = try await requestLocation()
        async let address = reverseGeocode(location)
        async let snapshot = mapSnapshot(location)
        return VisitPlace(address: try await address, mapSnapshotData: try await snapshot)
    }

    private func requestLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.first else {
                continuation?.resume(throwing: CLError(.locationUnknown))
                continuation = nil
                return
            }
            continuation?.resume(returning: location)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> String {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else { return "" }
        return [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func mapSnapshot(_ location: CLLocation) async throws -> Data {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 700,
            longitudinalMeters: 700
        )
        options.size = CGSize(width: 320, height: 220)
        let snapshot = try await MKMapSnapshotter(options: options).start()
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: options.size)
        let image = renderer.image { _ in
            snapshot.image.draw(at: .zero)
            let point = snapshot.point(for: location.coordinate)
            let pin = UIImage(systemName: "mappin.circle.fill")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
            let pinSize = CGSize(width: 34, height: 34)
            pin?.draw(in: CGRect(x: point.x - pinSize.width / 2, y: point.y - pinSize.height, width: pinSize.width, height: pinSize.height))
        }
        return image.jpegData(compressionQuality: 0.82) ?? Data()
        #else
        return Data()
        #endif
    }
}

struct VisitPlace {
    var address: String
    var mapSnapshotData: Data
}

#if os(iOS)
extension NativeAppState {
    func transcribeVoiceMemoIfNeeded(logId: String) {
        guard let log = visitLogs.first(where: { $0.id == logId }),
              log.kind == .voiceMemo,
              let fileName = log.audioFileName else {
            return
        }

        updateVoiceTranscription(logId: logId, transcript: nil, status: .transcribing)
        let url = assetURL(fileName: fileName)
        Task {
            do {
                let output = try await VoiceMemoTranscriber.transcribe(url: url)
                updateVoiceTranscription(
                    logId: logId,
                    transcript: output.transcript,
                    status: .completed,
                    segments: output.segments
                )
            } catch {
                updateVoiceTranscription(logId: logId, transcript: nil, status: .failed)
            }
        }
    }
}

struct VoiceTranscriptionOutput {
    let transcript: String
    let segments: [VoiceTranscriptionSegment]
}

enum VoiceMemoTranscriber {
    static func transcribe(url: URL) async throws -> VoiceTranscriptionOutput {
        let authorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authorizationStatus == .authorized else { throw VoiceTranscriptionError.permissionDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko_KR")), recognizer.isAvailable else {
            throw VoiceTranscriptionError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            var task: SFSpeechRecognitionTask?
            var didResume = false
            func finish(_ result: Result<VoiceTranscriptionOutput, Error>) {
                guard !didResume else { return }
                didResume = true
                task?.cancel()
                switch result {
                case .success(let transcript):
                    continuation.resume(returning: transcript)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let transcription = result.bestTranscription
                    let segments = transcription.segments.enumerated().compactMap { index, segment -> VoiceTranscriptionSegment? in
                        let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return nil }
                        return VoiceTranscriptionSegment(
                            id: "\(index)-\(Int(segment.timestamp * 1000))",
                            text: text,
                            timestamp: segment.timestamp,
                            duration: segment.duration
                        )
                    }
                    finish(.success(VoiceTranscriptionOutput(transcript: transcription.formattedString, segments: segments)))
                    return
                }
                if let error {
                    finish(.failure(error))
                }
            }
        }
    }
}

private enum VoiceTranscriptionError: Error {
    case permissionDenied
    case unavailable
}
#else
extension NativeAppState {
    func transcribeVoiceMemoIfNeeded(logId: String) {}
}
#endif
