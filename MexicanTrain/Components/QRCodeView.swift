import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let payload: String
    var foreground: Color = .black
    var background: Color = .white

    var body: some View {
        let image = makeImage()
        return Image(uiImage: image)
            .resizable()
            .interpolation(.none)
            .aspectRatio(1, contentMode: .fit)
    }

    private func makeImage() -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else {
            return UIImage(systemName: "qrcode") ?? UIImage()
        }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        if let cg = context.createCGImage(scaled, from: scaled.extent) {
            return UIImage(cgImage: cg)
        }
        return UIImage()
    }
}
