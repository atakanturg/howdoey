// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Howdoey", platforms: [.macOS(.v14)],
    products: [.executable(name: "Howdoey", targets: ["Howdoey"])],
    targets: [
        .target(name: "HowdoeyCore"),
        .executableTarget(name: "Howdoey", dependencies: ["HowdoeyCore"], exclude: ["UI/TESTING.md"]),
        .executableTarget(name: "HowdoeyChecks", dependencies: ["HowdoeyCore"], path: "Tests/HowdoeyCoreTests")
    ]
)
