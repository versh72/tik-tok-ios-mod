// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetDiag",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NetDiagCore", targets: ["NetDiagCore"]),
        .library(name: "NetDiagEngine", targets: ["NetDiagEngine"]),
        .library(name: "NetDiagUI", targets: ["NetDiagUI"])
    ],
    targets: [
        // Pure decision logic. No UIKit, no Network framework, no AppKit.
        // This is the only target the unit tests depend on, so the whole
        // test suite runs on any platform with a Swift toolchain.
        .target(name: "NetDiagCore"),

        // Network.framework probes. Apple platforms only.
        .target(name: "NetDiagEngine", dependencies: ["NetDiagCore"]),

        // SwiftUI surface. Apple platforms only.
        .target(name: "NetDiagUI", dependencies: ["NetDiagCore", "NetDiagEngine"]),

        .testTarget(
            name: "NetDiagCoreTests",
            dependencies: ["NetDiagCore"]
        )
    ]
)