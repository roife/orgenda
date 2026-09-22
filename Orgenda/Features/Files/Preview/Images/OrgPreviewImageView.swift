import SwiftUI
import UIKit

struct OrgPreviewImageContext {
    let store: WorkspaceStore
    let documentPath: String
}

private struct OrgPreviewImageContextKey: EnvironmentKey {
    static let defaultValue: OrgPreviewImageContext? = nil
}

extension EnvironmentValues {
    var orgPreviewImageContext: OrgPreviewImageContext? {
        get { self[OrgPreviewImageContextKey.self] }
        set { self[OrgPreviewImageContextKey.self] = newValue }
    }
}

/// Images occupy their own line while surrounding rich text and math retain
/// their order. Image paths remain presentation data, never source mutations.
struct OrgPreviewImageFlow: View {
    enum Segment {
        case text([OrgPreviewInlineFragment])
        case image(OrgPreviewImageReference)
    }

    let fragments: [OrgPreviewInlineFragment]
    var textStyle: UIFont.TextStyle = .body

    static func segments(_ fragments: [OrgPreviewInlineFragment]) -> [Segment] {
        var result: [Segment] = []
        var text: [OrgPreviewInlineFragment] = []
        func flush() {
            let hasContent = text.contains {
                if case .text(let value) = $0 {
                    return !value.characters.allSatisfy(\.isWhitespace)
                }
                return true
            }
            if hasContent { result.append(.text(text)) }
            text.removeAll(keepingCapacity: true)
        }
        for fragment in fragments {
            if case .image(let reference) = fragment {
                flush()
                result.append(.image(reference))
            } else {
                text.append(fragment)
            }
        }
        flush()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.segments(fragments).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let fragments):
                    OrgPreviewInlineText(fragments: fragments, textStyle: textStyle)
                        .fixedSize(horizontal: false, vertical: true)
                case .image(let reference):
                    OrgPreviewImageView(reference: reference)
                }
            }
        }
    }
}

struct OrgPreviewImageView: View {
    @Environment(\.orgPreviewImageContext) private var context
    let reference: OrgPreviewImageReference
    @State private var loadedImage: UIImage?
    @State private var loadedRequest: Request?
    @State private var errorMessage: String?
    @State private var retry = 0
    @State private var presentedImage: Presentation?

    private struct Presentation: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private struct Request: Hashable {
        let workspaceID: UUID?
        let paths: [String]
        let failure: String?
        let retry: Int
    }

    private var request: Request {
        do {
            let paths = try reference.candidates(
                documentPath: context?.documentPath ?? "",
                document: context.flatMap { $0.store.parsedDocuments[$0.documentPath] }
            )
            return Request(workspaceID: context?.store.workspaceFileSessionID, paths: paths, failure: nil, retry: retry)
        } catch {
            return Request(workspaceID: context?.store.workspaceFileSessionID, paths: [],
                           failure: error.localizedDescription, retry: retry)
        }
    }

    var body: some View {
        let request = request
        Group {
            if loadedRequest == request, let image = loadedImage {
                Button { presentedImage = Presentation(image: image) } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reference.label)
                .accessibilityHint("Open image. Pinch to zoom.")
                .accessibilityIdentifier("org.preview.image.\(reference.startByte)")
                .contextMenu {
                    Button("Reload image", systemImage: "arrow.clockwise") { retry += 1 }
                }
            } else if let message = request.failure ?? (loadedRequest == request ? errorMessage : nil) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn't load image", systemImage: "photo.badge.exclamationmark")
                        .font(.subheadline.weight(.semibold))
                    Text(reference.label).font(.footnote).foregroundStyle(.secondary)
                    Text(message).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    Button("Retry", systemImage: "arrow.clockwise") { retry += 1 }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("org.preview.image.retry.\(reference.startByte)")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ProgressView("Loading image…")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, minHeight: 88)
            }
        }
        .task(id: request) {
            loadedRequest = request
            loadedImage = nil
            errorMessage = nil
            guard request.failure == nil else { return }
            do {
                let image = try await OrgPreviewImageLoader.shared.load(
                    candidates: request.paths, fileStore: context?.store.fileStore,
                    workspaceID: request.workspaceID ?? UUID()
                )
                try Task.checkCancellation()
                loadedImage = image
            } catch is CancellationError {
                // Leaving Preview should not turn an interrupted load into an error.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $presentedImage) { presentation in
            OrgPreviewImageSheet(image: presentation.image, title: reference.label)
        }
    }
}

private struct OrgPreviewImageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let title: String

    var body: some View {
        NavigationStack {
            OrgZoomableImage(image: image, label: title)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "xmark", role: .close) { dismiss() }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("org.preview.image.close")
                    }
                }
        }
    }
}

private struct OrgZoomableImage: UIViewRepresentable {
    let image: UIImage
    let label: String

    func makeUIView(context: Context) -> ImageScrollView { ImageScrollView() }

    func updateUIView(_ view: ImageScrollView, context: Context) {
        if view.imageView.image !== image {
            view.setZoomScale(1, animated: false)
            view.imageView.image = image
            view.imageView.frame = CGRect(origin: .zero, size: image.size)
            view.contentSize = image.size
            view.fittedSize = .zero
        }
        view.imageView.isAccessibilityElement = true
        view.imageView.accessibilityLabel = label
        view.setNeedsLayout()
    }

    final class ImageScrollView: UIScrollView, UIScrollViewDelegate {
        let imageView = UIImageView()
        var fittedSize: CGSize = .zero

        init() {
            super.init(frame: .zero)
            delegate = self
            accessibilityIdentifier = "org.preview.image.zoom"
            addSubview(imageView)
            showsVerticalScrollIndicator = false
            showsHorizontalScrollIndicator = false
            backgroundColor = .systemBackground
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size != fittedSize, bounds.width > 0, bounds.height > 0,
               let size = imageView.image?.size, size.width > 0, size.height > 0 {
                fittedSize = bounds.size
                let fit = min(bounds.width / size.width, bounds.height / size.height, 1)
                minimumZoomScale = fit
                maximumZoomScale = max(1, fit * 5)
                setZoomScale(fit, animated: false)
            }
            centerImage()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

        private func centerImage() {
            let horizontal = max(0, (bounds.width - imageView.frame.width) / 2)
            let vertical = max(0, (bounds.height - imageView.frame.height) / 2)
            let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
            if contentInset != inset { contentInset = inset }
        }

        @objc private func toggleZoom() {
            let target = zoomScale > minimumZoomScale ? minimumZoomScale : min(maximumZoomScale, minimumZoomScale * 2.5)
            setZoomScale(target, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
}
