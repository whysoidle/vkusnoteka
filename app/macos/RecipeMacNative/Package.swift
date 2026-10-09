// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "RecipeMacNative",
  platforms: [.macOS(.v12)],
  products: [.library(name: "RecipeMacNative", targets: ["RecipeMacNative"])],
  targets: [
    .binaryTarget(
      name: "CLiteRTLM_mac",
      url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.18.0/CLiteRTLM_mac.xcframework.zip",
      checksum: "5f6ee68d95eeccb084c6e66d5ee47255e3020fa0fb29696dd0301ae26d6cfb4f"),
    .target(name: "RecipeMacNative", dependencies: ["CLiteRTLM_mac"],
            resources: [.process("Resources")]),
  ]
)
