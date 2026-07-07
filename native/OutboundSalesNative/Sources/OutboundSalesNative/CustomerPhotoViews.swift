import OutboundSalesCore
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#endif
#if os(macOS)
import AppKit
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
    @State private var selectedPhotoLog: CustomerPhotoLog?

    private let columns = [
        GridItem(.adaptive(minimum: 92), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(displayedLogs)) { log in
                Button {
                    selectedPhotoLog = log
                } label: {
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
                .buttonStyle(.plain)
                .accessibilityLabel("사진 보기")
            }
        }
        .sheet(item: $selectedPhotoLog) { log in
            CustomerPhotoViewer(photoLogs: Array(displayedLogs), initialPhotoId: log.id)
                .environmentObject(state)
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
    @State private var selectedPhotoLog: CustomerPhotoLog?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                if let photoLog = entry.photoLog {
                    Button {
                        selectedPhotoLog = photoLog
                    } label: {
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
                    .buttonStyle(.plain)
                    .accessibilityLabel("사진 보기")
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
        .sheet(item: $selectedPhotoLog) { log in
            CustomerPhotoViewer(photoLogs: [log], initialPhotoId: log.id)
                .environmentObject(state)
        }
    }
}

struct CustomerPhotoViewer: View {
    @EnvironmentObject private var state: NativeAppState
    @Environment(\.dismiss) private var dismiss
    let photoLogs: [CustomerPhotoLog]
    @State private var selectedPhotoId: String

    init(photoLogs: [CustomerPhotoLog], initialPhotoId: String) {
        self.photoLogs = photoLogs
        self._selectedPhotoId = State(initialValue: initialPhotoId)
    }

    private var selectedPhotoLog: CustomerPhotoLog? {
        photoLogs.first { $0.id == selectedPhotoId } ?? photoLogs.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                photoPager
            }
            .navigationTitle("사진")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let selectedPhotoLog {
                        ShareLink(item: state.photoURL(for: selectedPhotoLog)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("사진 공유")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var photoPager: some View {
        let pager = TabView(selection: $selectedPhotoId) {
            ForEach(photoLogs) { log in
                ZStack(alignment: .bottomLeading) {
                    ZoomablePhotoView(url: state.photoURL(for: log))
                    if log.caption != nil || !photoLogs.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(log.createdAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption.weight(.semibold))
                            if let caption = log.caption, !caption.isEmpty {
                                Text(caption)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(14)
                    }
                }
                .tag(log.id)
            }
        }

        #if os(iOS)
        pager.tabViewStyle(.page(indexDisplayMode: photoLogs.count > 1 ? .automatic : .never))
        #else
        pager
        #endif
    }
}

#if os(iOS)
private struct ZoomablePhotoView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = UIImage(contentsOfFile: url.path)
        context.coordinator.imageView?.frame = scrollView.bounds
        if context.coordinator.currentURL != url {
            scrollView.setZoomScale(1, animated: false)
            context.coordinator.currentURL = url
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        var currentURL: URL?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let zoomScale = min(scrollView.maximumZoomScale, 3)
                let width = scrollView.bounds.width / zoomScale
                let height = scrollView.bounds.height / zoomScale
                let rect = CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
#elseif os(macOS)
private struct ZoomablePhotoView: View {
    let url: URL
    @State private var scale = 1.0

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = max(1, min(6, value.magnification))
                            }
                    )
            } else {
                ContentUnavailableView("사진을 열 수 없습니다.", systemImage: "photo")
                    .foregroundStyle(.white)
            }
        }
        .background(.black)
    }
}
#endif
