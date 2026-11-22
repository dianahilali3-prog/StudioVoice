#!/usr/bin/env bash
# Downloads the Supertonic 3 model pack (~400 MB) from Hugging Face.
#
# Usage:
#   ./scripts/download_models.sh                # → DianaVoiceStudio/Resources/SupertonicModels.bundle
#                                               #   (voices embedded in the app: works offline from the first launch)
#   ./scripts/download_models.sh /path/to/dir   # → any folder (unit tests, AirDrop/Files import…)
set -euo pipefail

DEST="${1:-$(cd "$(dirname "$0")/.." && pwd)/DianaVoiceStudio/Resources/SupertonicModels.bundle}"
MIRRORS=(
  "https://huggingface.co/Supertone/supertonic-3/resolve/main"
  "https://huggingface.co/lnkiai/supertonic-3-mirror/resolve/main"
)
FILES=(
  onnx/tts.json
  onnx/unicode_indexer.json
  onnx/duration_predictor.onnx
  onnx/text_encoder.onnx
  onnx/vector_estimator.onnx
  onnx/vocoder.onnx
)
for s in F1 F2 F3 F4 F5 M1 M2 M3 M4 M5; do FILES+=("voice_styles/$s.json"); done

mkdir -p "$DEST/onnx" "$DEST/voice_styles"
for f in "${FILES[@]}"; do
  if [[ -s "$DEST/$f" ]]; then
    echo "✓ $f (déjà présent)"
    continue
  fi
  ok=0
  for base in "${MIRRORS[@]}"; do
    echo "↓ $f"
    if curl -fL --retry 4 --retry-delay 3 -o "$DEST/$f.part" "$base/$f"; then
      mv "$DEST/$f.part" "$DEST/$f"
      ok=1
      break
    fi
  done
  if [[ $ok -ne 1 ]]; then
    echo "✗ Impossible de télécharger $f" >&2
    exit 1
  fi
done
echo "Modèles Supertonic 3 prêts dans : $DEST"
du -sh "$DEST" 2>/dev/null || true
