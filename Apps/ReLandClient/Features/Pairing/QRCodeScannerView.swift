import SwiftUI
import VisionKit

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(
        context: Context
    ) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.qr]),
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: DataScannerViewController,
        context _: Context
    ) {
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(
        _ controller: DataScannerViewController,
        coordinator _: Coordinator
    ) {
        controller.stopScanning()
    }

    final class Coordinator:
        NSObject,
        DataScannerViewControllerDelegate
    {
        private let onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems _: [RecognizedItem]
        ) {
            for item in addedItems {
                guard
                    case let .barcode(barcode) = item,
                    let value = barcode.payloadStringValue,
                    value.hasPrefix("reland-pair:v2:")
                else {
                    continue
                }
                onCode(value)
                return
            }
        }
    }
}
