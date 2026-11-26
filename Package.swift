// swift-tools-version:6.0
import PackageDescription

let lame = "/opt/homebrew/lib/libmp3lame.a"

let package = Package(
    name: "mSOUND",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MSoundEngine", targets: ["MSoundEngine"]),
        .executable(name: "msound-cli", targets: ["msound-cli"]),
        .executable(name: "mSOUND", targets: ["mSOUND"]),
        .executable(name: "mSOUNDFinder", targets: ["mSOUNDFinder"]),
    ],
    targets: [
        .target(name: "CLame", path: "Sources/CLame",
                cSettings: [.unsafeFlags(["-I/opt/homebrew/include"])]),
        .target(name: "MSoundEngine", dependencies: ["CLame"], path: "Sources/MSoundEngine",
                linkerSettings: [.unsafeFlags([lame, "/opt/homebrew/lib/libmpg123.a"]),
                                 .linkedFramework("AudioToolbox"), .linkedFramework("AVFoundation")]),
        .target(name: "MSoundShared", path: "Sources/MSoundShared"),
        .executableTarget(name: "mSOUND", dependencies: ["MSoundEngine", "MSoundShared"], path: "Sources/App"),
        .executableTarget(name: "mSOUNDFinder", dependencies: ["MSoundShared"], path: "Sources/FinderExt",
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
                                           .linkedFramework("FinderSync"), .linkedFramework("Cocoa")]),
        .executableTarget(name: "msound-cli", dependencies: ["MSoundEngine"], path: "Sources/msound-cli"),
        .testTarget(name: "MSoundEngineTests", dependencies: ["MSoundEngine"], path: "Tests/MSoundEngineTests"),
    ],
    swiftLanguageModes: [.v5]
)
