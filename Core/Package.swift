// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AlterEgoCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AlterEgoCore", targets: ["AlterEgoCore"]),
               .executable(name: "alter-ego", targets: ["AlterEgoHarness"])],
    targets: [.target(name: "AlterEgoCore"),
              .executableTarget(name: "AlterEgoHarness", dependencies: ["AlterEgoCore"]),
              .testTarget(name: "AlterEgoCoreTests", dependencies: ["AlterEgoCore"])]
)
