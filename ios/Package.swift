// swift-tools-version:5.9
// Lets the layout engine (PrintSizing/Layout) be unit tested with `swift test`
// without Xcode. The app target compiles the same files directly.
import PackageDescription

let package = Package(
    name: "PrintLayout",
    targets: [
        .target(name: "PrintLayout", path: "PrintSizing/Layout"),
        .testTarget(name: "PrintLayoutTests", dependencies: ["PrintLayout"], path: "PrintLayoutTests"),
    ]
)
