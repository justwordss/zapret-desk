// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ZapretDesk", platforms: [.macOS(.v13)], products: [.executable(name: "ZapretDesk", targets: ["ZapretDesk"])], targets: [.executableTarget(name: "ZapretDesk")], swiftLanguageModes: [.v5])
