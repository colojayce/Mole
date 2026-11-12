// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MoleUI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MoleUI", targets: ["MoleUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.3"),
    ],
    targets: [
        .target(name: "MoleKit"),
        .executableTarget(
            name: "MoleUI",
            dependencies: [
                "MoleKit",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .testTarget(
            name: "MoleKitTests",
            dependencies: ["MoleKit"]
        ),
    ]
)
