// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MacBridgeAgent",
    platforms: [.macOS("26.0")],
    products: [.library(name: "MacBridgeCore", targets: ["MacBridgeCore"]),
               .executable(name: "ProtocolProbe", targets: ["ProtocolProbe"]),
               .executable(name: "MacBridge", targets: ["MacBridge"]),
               .executable(name: "MacBridgeLab", targets: ["MacBridgeLab"])],
    targets: [.target(name: "MacBridgeCore"),
              .target(name: "MacBridgeNative", dependencies: ["MacBridgeCore"]),
              .executableTarget(name: "MacBridge", dependencies: ["MacBridgeCore", "MacBridgeNative"]),
              .executableTarget(name: "MacBridgeLab", dependencies: ["MacBridgeCore", "MacBridgeNative"]),
              .testTarget(name: "MacBridgeNativeTests", dependencies: ["MacBridgeCore", "MacBridgeNative"]),
              .executableTarget(name: "ProtocolProbe", dependencies: ["MacBridgeCore"]),
              .executableTarget(name: "NativeStateProbe", dependencies: ["MacBridgeCore", "MacBridgeNative"]),
              .executableTarget(name: "PolicyChecks", dependencies: ["MacBridgeCore"])],
    swiftLanguageModes: [.v6])
