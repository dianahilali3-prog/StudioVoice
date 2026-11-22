#!/usr/bin/env python3
"""DianaVoiceStudio · générateur de voix off open source (Chatterbox Multilingual, licence MIT).

Utilisé par .github/workflows/voix-off.yml, mais fonctionne aussi sur n'importe quel ordinateur :

    python voixoff/generate.py plan  --request demandes/ma-demande.txt --parts 4 --out plan.json
    python voixoff/generate.py synth --plan plan.json --part 0 --out parts/      (une fois par partie)
    python voixoff/generate.py merge --plan plan.json --parts-dir parts/ --out sortie/

Format d'une demande (fichier texte) : quelques réglages, une ligne « --- », puis le script.

    voix: clara
    vitesse: 1.0
    emotion: 0.5
    langue: auto
    titre: Ma vidéo
    ---
    Bonjour à toutes et à tous…
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
VOICES = json.loads((HERE / "voices.json").read_text(encoding="utf-8"))
MAX_CHARS = 250  # Chatterbox lit au mieux des segments courts
SR_OUT = 44100

# ---------------------------------------------------------------- demande

def parse_request(text):
    params = {"voix": "clara", "vitesse": "1.0", "emotion": "0.5", "hauteur": "0", "langue": "auto", "titre": ""}
    if "\n---" in text or text.startswith("---"):
        head, _, body = text.partition("---")
        for line in head.splitlines():
            if ":" in line:
                k, _, v = line.partition(":")
                params[k.strip().lower()] = v.strip()
        script = body.lstrip("-\n")
    else:
        script = text
    return params, script.strip()


def voice_by_id(vid):
    vid = (vid or "").strip().lower()
    for v in VOICES:
        if v["id"] == vid or v["name"].lower() == vid:
            return v
    if vid.startswith("fichier:"):  # voix personnelle déposée dans le dépôt (ta propre voix uniquement)
        return {"id": vid, "name": "Voix personnelle", "file": vid.split(":", 1)[1].strip(), "origin": "xx"}
    return VOICES[0]

# ---------------------------------------------------------------- découpage (mêmes règles que l'app)

TERM = ".!?…;؟؛"
ABBR = {"m", "mme", "mlle", "dr", "pr", "st", "ste", "cf", "ex", "etc", "vol", "chap", "fig", "av", "bd", "mr", "mrs"}


def split_sentences(par):
    out, cur, i = [], "", 0
    while i < len(par):
        c = par[i]
        cur += c
        if c in TERM:
            j = i + 1
            while j < len(par) and (par[j] in TERM or par[j] in "\"'»”’)]"):
                cur += par[j]
                j += 1
            end = j >= len(par) or par[j].isspace()
            word = re.findall(r"(\w+)\.$", cur.strip())
            if end and not (c == "." and word and word[-1].lower() in ABBR and j < len(par)):
                if cur.strip():
                    out.append(cur.strip())
                cur = ""
            i = j
            continue
        i += 1
    if cur.strip():
        out.append(cur.strip())
    return out


def split_long(s, max_len):
    parts, cur = [], ""
    for piece in re.split(r"(?<=[,،:])\s+", s):
        for w in (piece.split(" ") if len(piece) > max_len else [piece]):
            if not cur:
                cur = w
            elif len(cur) + 1 + len(w) <= max_len:
                cur += " " + w
            else:
                parts.append(cur)
                cur = w
    if cur:
        parts.append(cur)
    return parts


def detect_lang(text):
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return None
    arabic = sum(1 for c in letters if "؀" <= c <= "ۿ" or "ݐ" <= c <= "ݿ" or "ﭐ" <= c <= "﻿")
    return "ar" if arabic / len(letters) >= 0.5 else "fr"


def chunk_script(script, forced_lang):
    chunks = []
    paragraphs = [p.strip() for p in re.split(r"\r?\n", script) if re.search(r"\w", p)]
    for p in paragraphs:
        sents = []
        for s in split_sentences(p):
            sents.extend(split_long(s, MAX_CHARS) if len(s) > MAX_CHARS else [s])
        # regroupe les phrases courtes de la même langue jusqu'à MAX_CHARS
        group = []
        for s in sents:
            lang = forced_lang if forced_lang in ("fr", "ar") else (detect_lang(s) or "fr")
            if group and group[-1]["lang"] == lang and len(group[-1]["text"]) + 1 + len(s) <= MAX_CHARS:
                group[-1]["text"] += " " + s
            else:
                group.append({"text": s, "lang": lang, "pause": "sentence"})
        if group:
            group[-1]["pause"] = "paragraph"
            chunks.extend(group)
    if chunks:
        chunks[-1]["pause"] = "none"
    return chunks

# ---------------------------------------------------------------- commandes


def cmd_plan(args):
    params, script = parse_request(Path(args.request).read_text(encoding="utf-8"))
    voice = voice_by_id(params.get("voix"))
    chunks = chunk_script(script, params.get("langue", "auto").lower())
    if not chunks:
        sys.exit("Le script est vide.")
    n = max(1, min(args.parts, len(chunks)))
    size = -(-len(chunks) // n)
    for i, c in enumerate(chunks):
        c["index"] = i
        c["part"] = i // size
    plan = {
        "voice": voice,
        "speed": min(2.0, max(0.5, float(params.get("vitesse", 1) or 1))),
        "emotion": min(1.5, max(0.25, float(params.get("emotion", 0.5) or 0.5))),
        "pitch": min(6.0, max(-6.0, float(params.get("hauteur", 0) or 0))),
        "title": params.get("titre") or script.split("\n")[0][:60],
        "parts": -(-len(chunks) // size),
        "chunks": chunks,
        "characters": sum(len(c["text"]) for c in chunks),
    }
    Path(args.out).write_text(json.dumps(plan, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({"parts": plan["parts"], "chunks": len(chunks), "characters": plan["characters"], "voice": voice["name"]}))


def reference_audio(voice, cache_dir):
    cache_dir.mkdir(parents=True, exist_ok=True)
    if voice.get("file"):
        src = Path(voice["file"])
        if not src.exists():
            sys.exit(f"Fichier de voix introuvable : {src}")
    else:
        src = cache_dir / (voice["id"] + Path(voice["url"]).suffix)
        if not src.exists():
            urllib.request.urlretrieve(voice["url"], src)
    ref = cache_dir / (voice["id"].replace(":", "_").replace("/", "_") + ".ref.wav")
    if not ref.exists():
        # 12 premières secondes, mono 24 kHz
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-t", "12", "-ac", "1", "-ar", "24000", str(ref)], check=True)
    return str(ref)


def companion_for(voice, lang):
    """Voix qui lira un passage dans `lang` : la voix choisie si elle prononce bien cette langue
    (d'après le test du catalogue), sinon une voix native du même genre."""
    if voice.get(lang, True) or voice.get("file"):
        return voice
    natives = [v for v in VOICES if v.get("origin") == lang and v.get(lang, True)]
    same = [v for v in natives if v.get("gender") == voice.get("gender")]
    return (same or natives or [voice])[0]


def cmd_synth(args):
    import numpy as np
    import soundfile as sf
    import torch
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS

    plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    mine = [c for c in plan["chunks"] if c["part"] == args.part]
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    if not mine:
        return
    torch.set_num_threads(os.cpu_count() or 4)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = ChatterboxMultilingualTTS.from_pretrained(device=device)
    voice = plan["voice"]
    refs = {}
    for c in mine:
        v = companion_for(voice, c["lang"])
        if v["id"] not in refs:
            refs[v["id"]] = reference_audio(v, Path(args.cache))
        ref = refs[v["id"]]
        same = v.get("origin") == c["lang"]
        cfg = 0.5 if same else 0.0  # 0 = pas d'accent de la langue d'origine
        torch.manual_seed(1234 + c["index"])
        wav = model.generate(c["text"], language_id=c["lang"], audio_prompt_path=ref,
                             exaggeration=plan["emotion"], cfg_weight=cfg, temperature=0.8)
        sf.write(out / f"{c['index']:05d}.wav", wav.squeeze(0).cpu().numpy(), model.sr)
        print(f"[{c['index'] + 1}/{len(plan['chunks'])}] {c['lang']} {len(c['text'])} car.", flush=True)


def cmd_merge(args):
    import numpy as np
    import soundfile as sf

    plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    parts = Path(args.parts_dir)
    pieces, sr = [], 24000
    for c in plan["chunks"]:
        f = next(parts.rglob(f"{c['index']:05d}.wav"), None)
        if f is None:
            sys.exit(f"Segment manquant : {c['index']}")
        a, sr = sf.read(f, dtype="float32")
        if a.ndim > 1:
            a = a.mean(axis=1)
        # retire les silences de début / fin (marge 50 ms) et adoucit les bords
        idx = np.where(np.abs(a) > 0.01)[0]
        if len(idx):
            pad = int(0.05 * sr)
            a = a[max(0, idx[0] - pad): min(len(a), idx[-1] + pad)]
        fade = min(int(0.01 * sr), len(a) // 2)
        if fade:
            ramp = np.sin(np.linspace(0, np.pi / 2, fade)) ** 2
            a[:fade] *= ramp
            a[-fade:] *= ramp[::-1]
        pieces.append(a)
        pause = {"paragraph": 0.65, "sentence": 0.3, "none": 0.0}[c["pause"]]
        if pause:
            pieces.append(np.zeros(int(pause * sr), dtype=np.float32))
    audio = np.concatenate(pieces) if pieces else np.zeros(1, dtype=np.float32)
    peak = float(np.max(np.abs(audio))) or 1.0
    audio = audio * min(0.89 / peak, 4.0)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    raw = out / "raw.wav"
    sf.write(raw, audio, sr)
    title = re.sub(r"[^\w\- ]+", " ", plan.get("title") or "voix-off").strip()[:50] or "voix-off"
    base = out / title.replace(" ", "-")
    tempo = plan["speed"]
    filters = []
    semitones = plan.get("pitch", 0) or 0
    if abs(semitones) > 0.01:  # change la hauteur sans changer la durée
        r = 2 ** (semitones / 12)
        filters += [f"asetrate={int(sr * r)}", f"aresample={sr}", f"atempo={1 / r:.6f}"]
    if abs(tempo - 1) > 0.01:
        filters.append(f"atempo={tempo}")
    filt = ",".join(filters) or "anull"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw), "-af", filt, "-ar", str(SR_OUT), "-ac", "1",
                    "-c:a", "pcm_s16le", str(base) + ".wav"], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(base) + ".wav", "-c:a", "libmp3lame", "-b:a", "192k",
                    str(base) + ".mp3"], check=True)
    raw.unlink()
    duration = len(audio) / sr / tempo
    info = {"title": plan.get("title"), "voice": plan["voice"]["name"], "duration": round(duration, 1),
            "characters": plan["characters"], "files": [base.name + ".mp3", base.name + ".wav"]}
    (out / "info.json").write_text(json.dumps(info, ensure_ascii=False), encoding="utf-8")
    m, sec = divmod(int(round(duration)), 60)
    (out / "title.txt").write_text((plan.get("title") or "Voix off")[:80], encoding="utf-8")
    (out / "notes.txt").write_text(f"Voix : {info['voice']} · durée {m}:{sec:02d} · {info['characters']} caractères", encoding="utf-8")
    print(json.dumps(info, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan"); p.add_argument("--request", required=True); p.add_argument("--parts", type=int, default=1); p.add_argument("--out", required=True)
    s = sub.add_parser("synth"); s.add_argument("--plan", required=True); s.add_argument("--part", type=int, required=True); s.add_argument("--out", required=True); s.add_argument("--cache", default=str(Path.home() / ".cache" / "dianavoice"))
    m = sub.add_parser("merge"); m.add_argument("--plan", required=True); m.add_argument("--parts-dir", required=True); m.add_argument("--out", required=True)
    args = ap.parse_args()
    {"plan": cmd_plan, "synth": cmd_synth, "merge": cmd_merge}[args.cmd](args)


if __name__ == "__main__":
    main()
