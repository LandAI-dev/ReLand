import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QRCodeView: View {
    let value: String

    var body: some View {
        Group {
            if let image = qrImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var qrImage: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        let context = CIContext()
        guard
            let output = filter.outputImage?.transformed(
                by: CGAffineTransform(scaleX: 10, y: 10)
            ),
            let image = context.createCGImage(
                output,
                from: output.extent
            )
        else {
            return nil
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }
}
