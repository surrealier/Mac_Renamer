// swift-tools-version:5.9
import PackageDescription

// RenamerCore is pure Foundation (name transform, validation, rename engine) and
// builds/tests on any platform. The menu bar app needs AppKit, so it is only
// declared when the package is evaluated on macOS.
var products: [Product] = [
    .library(name: "RenamerCore", targets: ["RenamerCore"]),
]

var targets: [Target] = [
    .target(name: "RenamerCore"),
    .testTarget(name: "RenamerCoreTests", dependencies: ["RenamerCore"]),
]

#if os(macOS)
products.append(.executable(name: "MacRenamerApp", targets: ["MacRenamerApp"]))
targets.append(
    .executableTarget(
        name: "MacRenamerApp",
        dependencies: ["RenamerCore"],
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("Carbon"),
            .linkedFramework("ServiceManagement"),
        ]
    )
)
#endif

let package = Package(
    name: "Mac_Renamer",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
