import AppKit
import CoreImage.CIFilterBuiltins
import Vision
let url = "https://app.getwand.app/"
let filter = CIFilter.qrCodeGenerator()
filter.message = Data(url.utf8)
filter.correctionLevel = "M"
let output = filter.outputImage!
let scale = CGAffineTransform(scaleX: 8, y: 8)
let cg = CIContext().createCGImage(output.transformed(by: scale), from: output.extent.applying(scale))!
let bitmap = NSBitmapImageRep(cgImage: cg)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
let request = VNDetectBarcodesRequest()
try VNImageRequestHandler(cgImage: cg).perform([request])
guard request.results?.first?.payloadStringValue == url else { fatalError("QR does not decode to the dashboard") }
print("Verified QR destination: \(url)")
