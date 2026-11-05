// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Espresso",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Espresso", targets: ["Espresso"]),
    ],
    targets: [
        .target(name: "EspressoKit"),
        .executableTarget(name: "Espresso", dependencies: ["EspressoKit"]),
        .executableTarget(name: "espresso-render", dependencies: ["EspressoKit"]),
        .testTarget(name: "EspressoKitTests", dependencies: ["EspressoKit"]),
    ],
    swiftLanguageModes: [.v5]
)
