// swift-tools-version: 5.9
//
// Local copy of the ONNX Runtime Swift package (MIT, © Microsoft).
//
// Microsoft's `onnxruntime-swift-package-manager` repository was removed from
// GitHub in November 2026, so DianaVoiceStudio vendors it:
//   • `objectivec/`              Objective-C bindings 1.24.2 (unmodified, from the MIT source)
//   • `onnxruntime.xcframework`  ONNX Runtime 1.24.2 binary, extracted from Microsoft's
//                                official NuGet package by `scripts/setup.sh` (not committed: ~200 MB).
//
// Swift usage: `import OnnxRuntimeBindings`.
import PackageDescription

let package = Package(
    name: "onnxruntime",
    platforms: [.iOS(.v15), .macOS(.v14)],
    products: [
        .library(name: "onnxruntime", type: .static, targets: ["OnnxRuntimeBindings"]),
    ],
    targets: [
        .target(name: "OnnxRuntimeBindings",
                dependencies: ["onnxruntime"],
                path: "objectivec",
                cxxSettings: [.define("SPM_BUILD")]),
        .binaryTarget(name: "onnxruntime", path: "onnxruntime.xcframework"),
    ],
    cxxLanguageStandard: .cxx17
)
