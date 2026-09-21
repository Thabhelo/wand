import XCTest
import AppKit
@testable import MacBridgeNative

final class CaptureTests:XCTestCase {
    @MainActor func testWindowMatchingExcludesOverlaysAndRejectsAmbiguity() {
        let frame=CGRect(x:10,y:20,width:800,height:600)
        let window=DesktopControl.CaptureWindow.self
        let a=window.init(id:1,bounds:frame,layer:0,title:"Fixture")
        let overlay=window.init(id:2,bounds:frame,layer:20,title:"Fixture")
        XCTAssertEqual(DesktopControl.captureWindow([a,overlay],bounds:frame,title:"Fixture"),1)
        let duplicate=window.init(id:3,bounds:frame,layer:0,title:"Fixture")
        XCTAssertNil(DesktopControl.captureWindow([a,duplicate],bounds:frame,title:"Fixture"))
        XCTAssertNil(DesktopControl.captureWindow([overlay],bounds:frame,title:"Fixture"))
        XCTAssertFalse(DesktopControl.sameBounds(frame,frame.offsetBy(dx:40,dy:0)))
        XCTAssertFalse(DesktopControl.sameBounds(frame,CGRect(x:10,y:20,width:900,height:600)))
    }
    @MainActor func testNoisyRetinaCaptureFitsWireBudgetAndReportsActualDimensions() throws {
        let width=1600,height=1200
        var pixels=[UInt8](repeating:255,count:width*height*4)
        var seed:UInt32=42
        for i in pixels.indices where i%4 != 3 {
            seed = seed &* 1664525 &+ 1013904223;pixels[i]=UInt8(truncatingIfNeeded:seed >> 24)
        }
        let provider=CGDataProvider(data:Data(pixels) as CFData)!
        let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.noneSkipLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let encoded=try DesktopControl.encodeScreenshot(image)
        XCTAssertLessThanOrEqual(encoded.data.count,24000)
        let decoded=NSBitmapImageRep(data:encoded.data)!
        XCTAssertEqual(decoded.pixelsWide,Int(encoded.size.width))
        XCTAssertEqual(decoded.pixelsHigh,Int(encoded.size.height))
        XCTAssertLessThanOrEqual(decoded.pixelsWide,640)
        XCTAssertEqual(Double(decoded.pixelsWide)/Double(decoded.pixelsHigh),4.0/3.0,accuracy:0.02)
        XCTAssertThrowsError(try DesktopControl.encodeScreenshot(image,byteLimit:1))
    }
}
