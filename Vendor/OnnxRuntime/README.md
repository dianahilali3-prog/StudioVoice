# ONNX Runtime (vendored)

Local Swift package used by DianaVoiceStudio to run the Supertonic 3 voice models on device.

- `objectivec/` — Objective-C bindings of ONNX Runtime **1.24.2** (MIT, © Microsoft), unmodified apart
  from removing the training/test files, taken from the MIT source of
  `onnxruntime-swift-package-manager` (removed from GitHub in November 2026).
- `onnxruntime.xcframework` — **not committed**. `scripts/setup.sh` extracts it from Microsoft's official
  NuGet package `Microsoft.ML.OnnxRuntime` 1.24.2 (SHA-256 checked).

Swift: `import OnnxRuntimeBindings`.
