#!/usr/bin/env python3
"""Teste une voix candidate : génère un extrait FR et AR, vérifie la prononciation avec Whisper
et produit les extraits d'écoute (MP3) du studio. Usage : screen_voice.py <index> <dossier>"""
import difflib, json, re, subprocess, sys, urllib.request
from pathlib import Path
import numpy as np, soundfile as sf, torch
from chatterbox.mtl_tts import ChatterboxMultilingualTTS
from faster_whisper import WhisperModel
from scipy.signal import resample_poly

HERE = Path(__file__).resolve().parent
cand = json.loads((HERE / "candidates.json").read_text(encoding="utf-8"))[int(sys.argv[1])]
out = Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
TXT = {"fr": f"Bonjour, je m'appelle {cand['name']}. Je donne vie à vos vidéos avec une voix naturelle et chaleureuse.",
       "ar": "مرحبا بكم، يسعدني أن أقدم محتواكم بصوت طبيعي وواضح."}
src = out / ("src" + Path(cand["url"]).suffix); urllib.request.urlretrieve(cand["url"], src)
ref = out / "ref.wav"
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-t", "12", "-ac", "1", "-ar", "24000", str(ref)], check=True)
torch.set_num_threads(4)
model = ChatterboxMultilingualTTS.from_pretrained(device="cpu")
whisper = WhisperModel("small", device="cpu", compute_type="int8")
def norm(s):
    s = re.sub(r"[\u064B-\u065F\u0670\u0640]", "", s.lower())          # voyelles courtes arabes, tatweel
    s = re.sub("[أإآ]", "ا", s).replace("ى", "ي").replace("ة", "ه")
    return re.sub(r"[^\w\s]", "", s).split()
res = {**cand}
for lang in ("fr", "ar"):
    best = None
    for seed in (1, 2):  # deux essais, on garde le meilleur
        torch.manual_seed(seed)
        wav = model.generate(TXT[lang], language_id=lang, audio_prompt_path=str(ref), exaggeration=0.5,
                             cfg_weight=0.5 if cand["origin"] == lang else 0.0, temperature=0.8).squeeze(0).numpy()
        segs, _ = whisper.transcribe(resample_poly(wav, 16000, model.sr).astype(np.float32), language=lang)
        hyp = " ".join(s.text for s in segs)
        score = difflib.SequenceMatcher(None, norm(TXT[lang]), norm(hyp)).ratio()
        if best is None or score > best[0]:
            best = (score, wav, hyp)
        if score >= 0.95:
            break
    score, wav, hyp = best
    sf.write(out / f"{cand['id']}.{lang}.wav", wav, model.sr)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(out / f"{cand['id']}.{lang}.wav"), "-ac", "1", "-b:a", "96k",
                    str(out / f"{cand['id']}.{lang}.mp3")], check=True)
    (out / f"{cand['id']}.{lang}.wav").unlink()
    res[lang] = {"score": round(score, 3), "hyp": hyp}
src.unlink(); ref.unlink()
(out / f"{cand['id']}.json").write_text(json.dumps(res, ensure_ascii=False), encoding="utf-8")
print(json.dumps(res, ensure_ascii=False))
