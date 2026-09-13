// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AspaceI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AspaceI", targets: ["AspaceI"])
    ],
    targets: [
        .executableTarget(
            name: "AspaceI",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "AspaceITests",
            dependencies: ["AspaceI"]
        )
    ]
)
