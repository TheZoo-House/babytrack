// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "BabyCore", platforms: [.iOS(.v18), .macOS(.v14)], products: [.library(name: "BabyCore", targets: ["BabyCore"])], targets: [.target(name: "BabyCore", resources: [.process("Resources")]), .testTarget(name: "BabyCoreTests", dependencies: ["BabyCore"], resources: [.process("Resources")])])
