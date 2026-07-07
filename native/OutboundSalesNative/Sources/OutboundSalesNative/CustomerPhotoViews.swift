import OutboundSalesCore
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct CustomerPhotoCaptureSheet: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let customer: Customer
    @State private var caption = ""
    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    #else
    @State private var showingImageImporter = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("사진 기록") {
                    LabeledContent("고객", value: customer.name.isEmpty ? "이름 없음" : customer.name)
                    TextField("간단 메모", text: $caption, axis: .vertical)
                }

                Section("사진 추가") {
                    #if os(iOS)
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showingCamera = true
                        } else {
                            state.actionMessage = "이 기기에서는 카메라를 사용할 수 없습니다."
                        }
                    } label: {
                        Label("카메라로 촬영", systemImage: "camera.fill")
                    }

                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("사진앱에서 선택", systemImage: "photo.on.rectangle")
                    }
                    #else
                    Button {
                        showingImageImporter = true
                    } label: {
                        Label("이미지 파일 선택", systemImage: "photo.on.rectangle")
                    }
                    #endif
                }

                let photos = state.photos(for: customer)
                if !photos.isEmpty {
                    Section("최근 사진") {
                        CustomerPhotoGrid(photoLogs: photos, maxCount: 6)
                            .environmentObject(state)
                    }
                }
            }
            .navigationTitle("사진 기록")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            #if os(iOS)
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task { await addPhotoItem(item) }
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView { url in
                    addPhotoFile(url: url, source: .camera)
                }
            }
            #else
            .fileImporter(
                isPresented: $showingImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                addPhotoFile(url: url, source: .file)
            }
            #endif
        }
    }

    private func addPhotoFile(url: URL, source: CustomerPhotoSource) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            state.addPhoto(customer: customer, imageData: data, source: source, caption: caption)
            caption = ""
        } catch {
            state.actionMessage = "사진을 읽지 못했습니다."
        }
    }

    #if os(iOS)
    private func addPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                state.actionMessage = "사진을 읽지 못했습니다."
                return
            }
            state.addPhoto(customer: customer, imageData: data, source: .photoLibrary, caption: caption)
            caption = ""
            selectedPhotoItem = nil
        } catch {
            state.actionMessage = "사진을 읽지 못했습니다."
        }
    }
    #endif
}

struct CustomerPhotoGrid: View {
    @EnvironmentObject private var state: NativeAppState
    let photoLogs: [CustomerPhotoLog]
    var maxCount: Int? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 92), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(displayedLogs)) { log in
                VStack(alignment: .leading, spacing: 5) {
                    AsyncImage(url: state.photoURL(for: log, thumbnail: true)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text(log.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let caption = log.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var displayedLogs: [CustomerPhotoLog] {
        if let maxCount {
            return Array(photoLogs.prefix(maxCount))
        }
        return photoLogs
    }
}

struct CustomerHistoryEntryRow: View {
    @EnvironmentObject private var state: NativeAppState
    let entry: CustomerHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                if let photoLog = entry.photoLog {
                    AsyncImage(url: state.photoURL(for: photoLog, thumbnail: true)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 72, height: 72)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.headline)
                    Text(entry.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(entry.at, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
