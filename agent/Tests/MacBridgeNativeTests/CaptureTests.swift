import XCTest
import AppKit
import MacBridgeCore
@testable import MacBridgeNative

final class CaptureTests:XCTestCase {
    @MainActor func testCaptureEnumerationRetriesUntilTheSameTargetAppears() async throws {
        var requests=0,waits=0,checks=0
        let target:Int? = try await DesktopControl.awaitCaptureTarget(lookup:{
            requests += 1
            return requests==1 ? nil:17
        },validate:{ checks += 1 },pause:{ waits += 1 })
        XCTAssertEqual(target,17)
        XCTAssertEqual(requests,2)
        XCTAssertEqual(waits,1)
        XCTAssertEqual(checks,4)
    }
    @MainActor func testCaptureEnumerationCannotSucceedWhenTargetNeverAppears() async throws {
        var requests=0,waits=0
        let target:Int? = try await DesktopControl.awaitCaptureTarget(lookup:{ requests += 1; return nil },validate:{},pause:{ waits += 1 })
        XCTAssertNil(target)
        XCTAssertEqual(requests,3)
        XCTAssertEqual(waits,2)
    }
    @MainActor func testCaptureEnumerationAbortsAfterFocusOrPermissionChanges() async {
        for code in ["desktop_focus_changed","desktop_permission_required","device_locked","desktop_protected_ui"] {
            var changed=false,requests=0
            do {
                let _:Int? = try await DesktopControl.awaitCaptureTarget(lookup:{
                    requests += 1
                    changed=true
                    return 17
                },validate:{ if changed { throw ContractError(code:code) } },pause:{ XCTFail("Changed authorization or focus must not retry") })
                XCTFail("An enumeration result cannot survive changed authorization or focus")
            } catch { XCTAssertEqual((error as? ContractError)?.code,code) }
            XCTAssertEqual(requests,1)
        }
    }
    @MainActor func testCaptureEnumerationRechecksAfterWaiting() async {
        var changed=false,requests=0
        do {
            let _:Int? = try await DesktopControl.awaitCaptureTarget(lookup:{ requests += 1; return nil },validate:{
                if changed { throw ContractError(code:"desktop_focus_changed") }
            },pause:{ changed=true })
            XCTFail("Do not enumerate again after focus changed during the delay")
        } catch { XCTAssertEqual((error as? ContractError)?.code,"desktop_focus_changed") }
        XCTAssertEqual(requests,1)
    }
    @MainActor func testCaptureEnumerationDoesNotAcceptResultsAfterItsBudget() async throws {
        var clock=Date(timeIntervalSince1970:0),requests=0
        let target:Int? = try await DesktopControl.awaitCaptureTarget(lookup:{ requests += 1; clock=clock.addingTimeInterval(2.1); return 17 },validate:{},pause:{ XCTFail("The same deadline must govern every attempt") },now:{clock})
        XCTAssertNil(target)
        XCTAssertEqual(requests,1)
    }
    @MainActor func testCapturePermissionErrorIsNotRetried() async {
        var requests=0
        do {
            let _:Int? = try await DesktopControl.awaitCaptureTarget(lookup:{ requests += 1; throw ContractError(code:"screen_recording_permission_required") },validate:{},pause:{ XCTFail("Permission denial is not transient enumeration") })
            XCTFail("Capture must fail when permission is denied")
        } catch { XCTAssertEqual((error as? ContractError)?.code,"screen_recording_permission_required") }
        XCTAssertEqual(requests,1)
    }
    @MainActor func testWindowMatchingExcludesOverlaysAndRejectsAmbiguity() {
        let frame=CGRect(x:10,y:20,width:800,height:600)
        let window=DesktopControl.CaptureWindow.self
        let a=window.init(id:1,bounds:frame,layer:0,title:"Fixture")
        let overlay=window.init(id:2,bounds:frame,layer:20,title:"Fixture")
        XCTAssertEqual(DesktopControl.captureWindow([a,overlay],bounds:frame,title:"Fixture"),1)
        let duplicate=window.init(id:3,bounds:frame,layer:0,title:"Fixture")
        XCTAssertNil(DesktopControl.captureWindow([a,duplicate],bounds:frame,title:"Fixture"))
        XCTAssertNil(DesktopControl.captureWindow([overlay],bounds:frame,title:"Fixture"))
        let shifted=window.init(id:4,bounds:frame.offsetBy(dx:40,dy:0),layer:0,title:"Fixture")
        XCTAssertNil(DesktopControl.captureWindow([shifted],bounds:frame,title:"Fixture"))
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
