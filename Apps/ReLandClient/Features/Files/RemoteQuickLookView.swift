import QuickLook
import SwiftUI

struct RemoteQuickLookSheet: View {
    let title: String
    let fileURL: URL
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            RemoteQuickLookPreview(fileURL: fileURL)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: dismiss)
                    }
                }
        }
    }
}

private struct RemoteQuickLookPreview:
    UIViewControllerRepresentable
{
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    func makeUIViewController(
        context: Context
    ) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: QLPreviewController,
        context: Context
    ) {
        context.coordinator.fileURL = fileURL
        controller.reloadData()
    }

    final class Coordinator:
        NSObject,
        QLPreviewControllerDataSource
    {
        var fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(
            in _: QLPreviewController
        ) -> Int {
            1
        }

        func previewController(
            _: QLPreviewController,
            previewItemAt _: Int
        ) -> any QLPreviewItem {
            fileURL as NSURL
        }
    }
}
