import SwiftUI
import VisionKit

/// Wraps `VNDocumentCameraViewController` — the system document scanner (§6.1).
/// Not a custom camera capture: this is what gives edge-detection/perspective
/// correction for free, same reasoning documented in Phase0-Implementation-Logic-v2.md §6.1.
/// Present with `.fullScreenCover` — this controller expects to own the whole screen.
struct DocumentCameraScanner: UIViewControllerRepresentable {
    var onFinish: ([CGImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([CGImage]) -> Void
        private let onCancel: () -> Void

        init(onFinish: @escaping ([CGImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [CGImage] = []
            for pageIndex in 0..<scan.pageCount {
                if let cgImage = scan.imageOfPage(at: pageIndex).cgImage {
                    images.append(cgImage)
                }
            }
            onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            // Non-fatal from the caller's point of view — treat like cancel,
            // no page was produced either way.
            onCancel()
        }
    }
}
