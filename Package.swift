// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftyXrayKitCustom",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "SwiftyXrayKit", targets: ["SwiftyXrayKit"])
    ],
    targets: [
        .binaryTarget(
            name: "LibXray",
            path: "LibXray.xcframework.zip"
        ),
        .target(
            name: "SwiftyXrayKit",
            dependencies: ["LibXray"],
            path: "Sources/SwiftyXrayKit",
            linkerSettings: [.linkedLibrary("resolv")]
        )
    ]
)
