// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Kestrel", platforms: [.macOS(.v14)],
  products: [
    .library(name: "KestrelCore", targets: ["KestrelCore"]),
    .executable(name: "Kestrel", targets: ["Kestrel"]),
  ],
  targets: [
    .target(name: "KestrelCore"), .executableTarget(name: "Kestrel", dependencies: ["KestrelCore"]),
    .testTarget(name: "KestrelCoreTests", dependencies: ["KestrelCore"]),
    .testTarget(name: "KestrelNativeTests", dependencies: ["Kestrel", "KestrelCore"]),
  ],
  swiftLanguageModes: [.v5])
