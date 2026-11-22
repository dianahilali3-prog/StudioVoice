#!/usr/bin/env python3
"""Assemble docs/voices/voices.json et voixoff/voices.json à partir des résultats de screen_voice.py."""
import json, shutil, sys
from pathlib import Path
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
dst.mkdir(parents=True, exist_ok=True)
ORIG = {"fr": "française", "ar": "arabe", "en": "anglaise", "de": "allemande", "es": "espagnole", "pt": "portugaise", "it": "italienne"}
keep = []
for f in sorted(src.rglob("*.json")):
    r = json.loads(f.read_text(encoding="utf-8"))
    if "fr" not in r:
        continue
    # Whisper (petit modèle) est moins précis en arabe : seuil plus bas, et une voix d'origine
    # arabe est toujours acceptée en arabe (elle est lue avec ses propres réglages natifs).
    fr_ok = r["fr"]["score"] >= 0.85 or r["origin"] == "fr"
    ar_ok = r["ar"]["score"] >= 0.7 or r["origin"] == "ar"
    if not (fr_ok or ar_ok):
        continue
    preview = {}
    for lang, ok in (("fr", fr_ok), ("ar", ar_ok)):
        mp3 = f.parent / f"{r['id']}.{lang}.mp3"
        if ok and mp3.exists():
            shutil.copy(mp3, dst / mp3.name); preview[lang] = mp3.name
    g = {"F": "Femme", "M": "Homme"}.get(r["gender"], "Voix")
    desc = "Voix " + (f"d'origine {ORIG[r['origin']]}" if r["origin"] in ORIG else "internationale")
    keep.append({"id": r["id"], "name": r["name"], "gender": r["gender"] if r["gender"] in "FM" else "F", "origin": r["origin"],
                 "url": r["url"], "fr": fr_ok, "ar": ar_ok, "fr_score": r["fr"]["score"], "ar_score": r["ar"]["score"], "score": round((r["fr"]["score"] + r["ar"]["score"]) / 2, 3),
                 "reco": r["fr"]["score"] >= 0.95 and r["ar"]["score"] >= 0.85, "desc": desc, "preview": preview})
keep.sort(key=lambda v: (-v["reco"], -v["score"]))
(dst / "voices.json").write_text(json.dumps(keep, ensure_ascii=False, indent=1), encoding="utf-8")
Path("voixoff/voices.json").write_text(json.dumps([{k: v[k] for k in ("id", "name", "gender", "origin", "url", "fr", "ar")} for v in keep], ensure_ascii=False, indent=1), encoding="utf-8")
print(f"{len(keep)} voix gardées")
