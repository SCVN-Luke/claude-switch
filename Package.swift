// swift-tools-version: 6.0
import PackageDescription

// Command Line Tools ship Swift Testing outside the default framework search path.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltLibs = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "ClaudeSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeSwitchCore"),
        .executableTarget(name: "ClaudeSwitch", dependencies: ["ClaudeSwitchCore"]),
        .executableTarget(
            name: "ClaudeSwitchCoreTests",
            dependencies: ["ClaudeSwitchCore"],
            path: "Tests/ClaudeSwitchCoreTests",
            swiftSettings: [.unsafeFlags(["-F", cltFrameworks])],
            linkerSettings: [.unsafeFlags(["-F", cltFrameworks, "-framework", "Testing",
                                           "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
                                           "-Xlinker", "-rpath", "-Xlinker", cltLibs])]
        ),
    ]
)
