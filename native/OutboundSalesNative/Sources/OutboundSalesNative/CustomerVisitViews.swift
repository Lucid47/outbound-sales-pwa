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

#if os(iOS)
struct VisitVoiceMemoSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    let onSaved: () -> Void
    @StateObject private var recorder = VoiceMemoRecorder()
    @State private var memo = ""
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(customer.name.isEmpty ? "음성 메모" : customer.name) {
                    Text(recorder.isRecording ? "녹음 중..." : "녹음 버튼을 눌러 음성 메모를 남기세요.")
                        .foregroundStyle(recorder.isRecording ? .red : .secondary)
                    if recorder.duration > 0 {
                        LabeledContent("녹음 시간", value: Self.durationText(recorder.duration))
                    }
                    TextField("간단 메모", text: $memo, axis: .vertical)
                }

                Section {
                    Button {
                        Task { await toggleRecording() }
                    } label: {
                        Label(recorder.isRecording ? "녹음 중지" : "녹음 시작", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("저장") {
                        saveVoiceMemo()
                    }
                    .disabled(recorder.isRecording || recorder.recordedURL == nil)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleRecording() async {
        do {
            if recorder.isRecording {
                recorder.stop()
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
                memo: memo,
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
    @Published var recordedURL: URL?
    @Published var duration: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

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
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
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
        self.duration = 0
        self.isRecording = true
    }

    func stop() {
        recorder?.stop()
        if let startedAt {
            duration = Date().timeIntervalSince(startedAt)
        }
        isRecording = false
    }

    func cancel() {
        if isRecording {
            stop()
        }
    }
}

private enum VoiceMemoError: Error {
    case permissionDenied
}
#endif

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
                let transcript = try await VoiceMemoTranscriber.transcribe(url: url)
                updateVoiceTranscription(logId: logId, transcript: transcript, status: .completed)
            } catch {
                updateVoiceTranscription(logId: logId, transcript: nil, status: .failed)
            }
        }
    }
}

enum VoiceMemoTranscriber {
    static func transcribe(url: URL) async throws -> String {
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
            func finish(_ result: Result<String, Error>) {
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
                    finish(.success(result.bestTranscription.formattedString))
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
