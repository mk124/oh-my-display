// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "oh-my-display",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "OMDCore", targets: ["OMDCore"]),
  ],
  targets: [
    .target(
      name: "OMDQuartzBridge",
      publicHeadersPath: "include",
      linkerSettings: [
        .linkedFramework("QuartzCore"),
        .linkedFramework("CoreGraphics"),
      ]
    ),
    .target(
      name: "OMDCore",
      dependencies: ["OMDQuartzBridge"],
      linkerSettings: [
        .linkedFramework("CoreGraphics"),
        .linkedFramework("ColorSync"),
        .linkedFramework("IOKit"),
      ]
    ),
    .testTarget(
      name: "OMDCoreTests",
      dependencies: ["OMDCore", "OMDQuartzBridge"]
    ),
  ]
)
