// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Kestrel", platforms: [.macOS(.v14)],
  products: [
    .library(name: "KestrelCore", targets: ["KestrelCore"]),
    .executable(name: "Kestrel", targets: ["Kestrel"]),
  ],
  dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
  targets: [
    .target(name: "KestrelCore"),
    .executableTarget(
      name: "Kestrel",
      dependencies: ["KestrelCore", .product(name: "Sparkle", package: "Sparkle")],
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
      ]),
    .testTarget(name: "KestrelCoreTests", dependencies: ["KestrelCore"]),
    .testTarget(name: "KestrelNativeTests", dependencies: ["Kestrel", "KestrelCore"]),
  ],
  swiftLanguageModes: [.v5])
