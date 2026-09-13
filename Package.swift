// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AspaceI",
    defaultLocalization: "zh-Hant",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AspaceI", targets: ["AspaceI"])
    ],
    targets: [
        .executableTarget(
            name: "AspaceI",
            resources: [
                .copy("Resources/Logos"),
                .process("Resources/Localization")
            ],
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
