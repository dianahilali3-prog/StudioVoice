#!/usr/bin/env bash
# One-time setup before opening the project in Xcode.
#
# Fetches ONNX Runtime 1.24.2 for iOS from Microsoft's official NuGet package
# (Microsoft.ML.OnnxRuntime) and installs Vendor/OnnxRuntime/onnxruntime.xcframework.
#
# Usage:  ./scripts/setup.sh            # ONNX Runtime only
#         ./scripts/setup.sh --models   # + Supertonic voices embedded in the app (~400 MB)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.24.2"
SHA256="782564d3d68e87269ea1812cc94710ad06fe014faf093f01a6f89d0bd58719d3"
URL="https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${VERSION}/microsoft.ml.onnxruntime.${VERSION}.nupkg"
DEST="$ROOT/Vendor/OnnxRuntime/onnxruntime.xcframework"

if [[ -f "$DEST/Info.plist" && -f "$ROOT/Vendor/OnnxRuntime/.version" && "$(cat "$ROOT/Vendor/OnnxRuntime/.version")" == "$VERSION" ]]; then
  echo "✓ ONNX Runtime $VERSION déjà installé"
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "↓ ONNX Runtime $VERSION (NuGet officiel Microsoft, ~120 Mo)…"
  curl -fL --retry 4 --retry-delay 3 -o "$TMP/ort.nupkg" "$URL"
  if command -v shasum >/dev/null; then
    ACTUAL="$(shasum -a 256 "$TMP/ort.nupkg" | cut -d' ' -f1)"
  else
    ACTUAL="$(sha256sum "$TMP/ort.nupkg" | cut -d' ' -f1)"
  fi
  if [[ "$ACTUAL" != "$SHA256" ]]; then
    echo "✗ Somme de contrôle invalide ($ACTUAL)" >&2
    exit 1
  fi
  unzip -q -o "$TMP/ort.nupkg" "runtimes/ios/native/onnxruntime.xcframework.zip" -d "$TMP"
  rm -rf "$DEST"
  unzip -q "$TMP/runtimes/ios/native/onnxruntime.xcframework.zip" -d "$ROOT/Vendor/OnnxRuntime"
  echo "$VERSION" > "$ROOT/Vendor/OnnxRuntime/.version"
  echo "✓ $DEST"
fi

if [[ "${1:-}" == "--models" ]]; then
  "$ROOT/scripts/download_models.sh"
fi

echo "Prêt : ouvrez DianaVoiceStudio.xcodeproj dans Xcode."
