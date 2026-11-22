#!/usr/bin/env python3
"""Builds the model files served by the web version (web/index.html).

- text_encoder and vector_estimator are quantized to int8 (MatMul/Gemm/Conv, dynamic),
  duration_predictor and vocoder stay in float32 (the vocoder does not tolerate int8).
- Large files are split in 14 MB parts (`*.partN.dat.wasm`) so they can be published as
  artifact files; the page reassembles them and caches them in IndexedDB.

Usage: python3 scripts/build_web_models.py <supertonic-3 dir> <ort-wasm-simd-threaded.wasm> <out dir>
Requires: pip install onnxruntime onnx numpy
"""
import json, os, shutil, sys
import numpy as np
from onnxruntime.quantization import quantize_dynamic, QuantType

src, wasm, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
tmp = os.path.join(out, "_tmp"); os.makedirs(tmp, exist_ok=True)
files = {}
for name in ["duration_predictor", "text_encoder", "vector_estimator", "vocoder"]:
    path = os.path.join(src, "onnx", name + ".onnx")
    if name in ("text_encoder", "vector_estimator"):
        q = os.path.join(tmp, name + ".int8.onnx")
        quantize_dynamic(path, q, weight_type=QuantType.QUInt8, op_types_to_quantize=["MatMul", "Gemm", "Conv"])
        path = q
    files[name + ".onnx"] = path
CHUNK = 14_000_000
manifest = {"files": {}, "total": 0}
for name, path in files.items():
    data = open(path, "rb").read(); parts = []
    for i in range(0, len(data), CHUNK):
        fn = f"models/{name.split('.')[0]}.part{i // CHUNK}.dat.wasm"
        open(os.path.join(out, os.path.basename(fn)), "wb").write(data[i:i + CHUNK]); parts.append(fn)
    manifest["files"][name] = {"parts": parts, "size": len(data)}; manifest["total"] += len(data)
shutil.copy(os.path.join(src, "onnx", "unicode_indexer.json"), out)
for s in ["F1", "F2", "F3", "F4", "F5", "M1", "M2", "M3", "M4", "M5"]:
    d = json.load(open(os.path.join(src, "voice_styles", s + ".json")))
    compact = {k: {"dims": d[k]["dims"], "data": [round(float(v), 7) for v in np.array(d[k]["data"]).flatten()]} for k in ("style_ttl", "style_dp")}
    json.dump(compact, open(os.path.join(out, s + ".json"), "w"), separators=(",", ":"))
shutil.copy(wasm, os.path.join(out, "ort-wasm-simd-threaded.wasm"))
manifest["total"] += os.path.getsize(wasm)
json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)
shutil.rmtree(tmp)
print(f"{manifest['total'] / 1e6:.0f} MB written to {out}")
