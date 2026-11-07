// swift-tools-version:5.9
import PackageDescription

// Core/ is tetratorus/ascii-screenshot's macOS pipeline (minus the macOS capture/CLI), built here so its
// tests run on macOS and the iOS Simulator. The app target compiles Core/ directly (see project.yml).
let package = Package(
  name: "AsciiScreenCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [.library(name: "AsciiScreenCore", targets: ["AsciiScreenCore"])],
  targets: [
    .target(
      name: "AsciiScreenCore",
      path: "Core",
      swiftSettings: [.unsafeFlags(["-Ounchecked", "-wmo"], .when(configuration: .release))],
      linkerSettings: [.linkedLibrary("z"), .linkedLibrary("sqlite3")]
    ),
    .testTarget(name: "AsciiScreenCoreTests", dependencies: ["AsciiScreenCore"], path: "Tests/AsciiScreenCoreTests"),
  ]
)
