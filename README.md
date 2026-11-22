# DianaVoiceStudio

Application iOS native (SwiftUI) qui transforme un script en voix off, **entièrement sur l'iPhone** :
gratuite, sans compte, sans clé API, sans abonnement, et sans limite de caractères, de générations
ni de téléchargements. Voix **françaises** et **arabes**, **féminines** et **masculines**.

> Optimisée pour l'iPhone 17 Pro Max et compatible avec tous les iPhone sous **iOS 18 ou plus récent**.

---

## Sommaire

1. [Fonctionnalités](#fonctionnalités)
2. [Moteur vocal : pourquoi Supertonic 3](#moteur-vocal--pourquoi-supertonic-3)
3. [Compiler et installer sur un iPhone](#compiler-et-installer-sur-un-iphone)
4. [Utiliser l'application](#utiliser-lapplication)
5. [Architecture du projet](#architecture-du-projet)
6. [Tests](#tests)
7. [Checklist de livraison](#checklist-de-livraison)
8. [Licences](#licences)

---

## Fonctionnalités

| Fonction | Détail |
|---|---|
| **Script illimité** | Éditeur basé sur `UITextView` (fluide au-delà de 100 000 caractères), compteur de caractères / mots / durée estimée, bouton « Coller », support naturel de l'arabe (RTL). |
| **Découpage intelligent** | Coupe aux fins de phrase (`. ! ? … ; ؟ ؛`) en ignorant les abréviations (« M. », « Dr. », « etc. »), les initiales et les nombres décimaux. Chaque retour à la ligne crée une pause de paragraphe. Les phrases trop longues sont coupées aux virgules, puis aux mots. |
| **Assemblage fluide** | Les segments sont assemblés en *streaming* sur disque avec fondu enchaîné (équi-puissance) et pauses réglables : la mémoire reste constante, quelle que soit la longueur du script. |
| **20 voix neuronales** | 5 voix femmes + 5 voix hommes en **français**, idem en **arabe** (« Français – Femme · Camille », « Arabe – Homme · Karim »…), avec extrait d'écoute. |
| **Voix système Apple** | Les voix FR/AR installées dans iOS sont aussi proposées (utilisables immédiatement, hors ligne). |
| **Prosodie** | Vitesse **0,5× à 2×**, hauteur **±6 demi-tons**, 4 niveaux de qualité, pauses phrase / paragraphe, durée du fondu. |
| **Bilingue automatique** | Dans un script mixte, les passages en arabe sont lus en arabe et les passages en français en français, avec le même timbre. |
| **Lecteur** | Forme d'onde interactive, lecture / pause, ±10 s, lecture en arrière-plan. |
| **Téléchargement** | **WAV** (16 / 24 / 32 bits) ou **M4A/AAC** (128–256 kb/s) → « Enregistrer dans Fichiers » ou feuille de partage iOS. Une copie est aussi rangée dans *Fichiers › Sur mon iPhone › DianaVoiceStudio › Exports*. |
| **Bibliothèque** | Sauvegarde automatique de chaque projet (script + voix + réglages + audio), recherche, duplication, réexport. Une même graine garantit une interprétation identique à chaque régénération. |
| **Mode avion** | Une fois les voix installées, aucune connexion n'est utilisée. Les scripts ne quittent jamais l'iPhone. |
| **Design** | Rose poudré, noir et argent métallique, modes clair et sombre, gros boutons, retours haptiques et animations légères. |

---

## Moteur vocal : pourquoi Supertonic 3

Les trois options proposées ont été évaluées :

| Moteur | FR | AR femme | AR homme | Taille | Intégration iOS |
|---|---|---|---|---|---|
| Piper (rhasspy/piper-voices) | ✅ | ❌ aucune voix féminine (`ar_JO` = homme seul) | ✅ | ~60 Mo / voix | espeak-ng + ONNX à compiler |
| Voxtral TTS (port MLX) | ✅ | ⚠️ | ⚠️ | plusieurs Go, même en Q2 | lourd sur mobile |
| **Supertonic 3** | ✅ | ✅ | ✅ | **~400 Mo pour 31 langues et 10 timbres** | ONNX Runtime (SPM officiel) |

**Supertonic 3** est le seul à couvrir les 4 combinaisons (FR/AR × femme/homme) avec un seul modèle,
sans phonémiseur (il lit directement les caractères Unicode, donc pas d'espeak-ng à embarquer),
en 44,1 kHz, et très rapidement sur CPU. Il tourne via **ONNX Runtime 1.24.2**, aucune autre dépendance.

> ℹ️ Le dépôt GitHub `microsoft/onnxruntime-swift-package-manager` a été supprimé en novembre 2026.
> Pour que le projet reste compilable sans dépendre d'un miroir tiers, le paquet est **intégré localement**
> (`Vendor/OnnxRuntime` : liaisons Objective-C sous licence MIT + binaire extrait du paquet NuGet
> officiel de Microsoft par `scripts/setup.sh`).

Vérifications effectuées pendant le développement :

- le prétraitement Swift (`SupertonicTextProcessor`) produit **exactement les mêmes jetons** que
  l'implémentation de référence Python, en français et en arabe ;
- l'audio généré à partir de ces jetons pour *Français – Femme*, *Français – Homme*,
  *Arabe – Femme* et *Arabe – Homme* a été retranscrit mot pour mot par Whisper.

Le pack de modèles (`Supertone/supertonic-3` sur Hugging Face, avec un miroir public en secours)
est téléchargé **une seule fois** depuis l'onglet **Voix**. Il peut aussi être importé depuis
l'app Fichiers ou **embarqué directement dans l'application** (voir plus bas).

---

## Compiler et installer sur un iPhone

### Prérequis

- Un Mac avec **Xcode 16** ou plus récent (iOS 18 SDK).
- Un iPhone sous **iOS 18+** et un câble (ou le Wi-Fi de développement).
- Un **identifiant Apple** (gratuit suffit pour installer sur votre propre iPhone).

### Étapes

1. **Récupérer le projet**
   ```bash
   git clone https://github.com/dianahilali3-prog/StudioVoice.git
   cd StudioVoice
   ```
2. **Installer ONNX Runtime** (une seule fois, ~2 minutes) :
   ```bash
   ./scripts/setup.sh            # ou ./scripts/setup.sh --models pour embarquer aussi les voix
   ```
   Le script récupère ONNX Runtime 1.24.2 pour iOS depuis le paquet NuGet officiel de Microsoft
   (somme de contrôle vérifiée) et le place dans `Vendor/OnnxRuntime/`.
3. **Ouvrir** `DianaVoiceStudio.xcodeproj` dans Xcode.
4. **Signature** : sélectionnez la cible *DianaVoiceStudio* › onglet *Signing & Capabilities* ›
   cochez *Automatically manage signing* et choisissez votre *Team* (votre identifiant Apple).
   Si l'identifiant de bundle `studio.diana.voicestudio` est déjà pris, remplacez-le par un nom unique
   (ex. `com.votrenom.dianavoicestudio`).
5. **Brancher l'iPhone**, le choisir comme destination en haut de Xcode, puis **⌘R**.
6. Sur l'iPhone, la première fois : *Réglages › Confidentialité et sécurité › Mode développeur* → activer,
   puis *Réglages › Général › VPN et gestion de l'appareil* → faire confiance à votre profil développeur.

> Avec un identifiant Apple gratuit, Apple limite la validité de l'installation à 7 jours :
> il suffit de relancer ⌘R depuis Xcode. Un compte Apple Developer payant lève cette limite (1 an)
> et permet TestFlight.

### Option : voix embarquées dans l'app (zéro téléchargement)

Pour que l'application fonctionne hors ligne **dès la première ouverture** :

```bash
./scripts/download_models.sh
```

Le script place les modèles dans `DianaVoiceStudio/Resources/SupertonicModels.bundle`
(ignoré par git). Xcode les inclut automatiquement dans l'app (≈ +400 Mo) et l'onglet *Voix*
affiche « Inclus dans l'application ».

### Option : installer les voix sans Wi-Fi sur l'iPhone

Exécutez `./scripts/download_models.sh ~/Desktop/supertonic-3` sur le Mac, transférez le dossier
sur l'iPhone (AirDrop, iCloud Drive…), puis *Voix › Importer depuis Fichiers* et choisissez ce dossier.

---

## Utiliser l'application

1. **Onglet Voix** → *Télécharger les voix* (une seule fois, ~400 Mo, Wi-Fi conseillé).
   Vous pouvez aussi utiliser immédiatement une voix système Apple.
2. **Onglet Studio** :
   - donnez un titre (facultatif), collez ou écrivez votre script — aucune limite ;
   - *Choisir une voix* → filtrez par langue / genre, touchez ▶︎ pour écouter un extrait ;
   - ajustez la **vitesse** et la **hauteur** (et, dans *Réglages avancés*, les pauses, le fondu,
     la détection FR/AR, la normalisation) ;
   - touchez **Générer** : la progression (segments, durée produite, temps restant) s'affiche, et vous
     pouvez annuler à tout moment ;
   - **Écouter** avec le lecteur (forme d'onde cliquable, ±10 s) ;
   - **Télécharger** → choisissez *WAV* ou *M4A* → *Enregistrer dans Fichiers* ou *Partager…*.
3. **Bibliothèque** : tous vos projets sont enregistrés automatiquement ; touchez-en un pour le rouvrir,
   glissez pour le dupliquer ou le supprimer, appui long pour réexporter l'audio.
4. **Astuces** :
   - un retour à la ligne = pause longue ; les balises `<laugh>`, `<breath>`, `<sigh>` (menu ✨)
     ajoutent rire, respiration ou soupir ;
   - *Nouvelle interprétation* (réglages avancés) change l'intonation tout en gardant la voix ;
   - la qualité *Équilibrée* est le meilleur compromis ; *Studio* pour le rendu final.

**Performances indicatives** (iPhone récent, qualité Équilibrée) : la synthèse est nettement plus rapide
que le temps réel ; un script de 50 000 caractères (~55 min d'audio) se génère en quelques minutes.
L'écran reste allumé pendant la génération ; gardez l'app au premier plan pour les très longs scripts.

---

## Architecture du projet

```
DianaVoiceStudio.xcodeproj        Projet Xcode 16 (groupes synchronisés avec les dossiers)
Config/Info.plist                 Clés iOS (audio en arrière-plan, partage Fichiers, écran de lancement)
DianaVoiceStudio/
  App/                            Point d'entrée, AppModel (état global), réglages
  Core/
    Text/TextSegmenter            Découpage intelligent des longs scripts
    Text/LanguageDetector         Détection arabe / français par segment
    TTS/SupertonicTextProcessor   Front-end texte (port exact de la référence Python)
    TTS/SupertonicRuntime         4 graphes ONNX : durée → encodeur → flow matching → vocodeur
    TTS/SpeechEngine              Protocole moteur + moteur Supertonic (chargement paresseux, file dédiée)
    TTS/AppleSpeechEngine         Voix système (AVSpeechSynthesizer.write, hors ligne)
    TTS/SynthesisPipeline         Segmentation → synthèse en flux → assemblage → post-traitement
    Audio/AudioStitcher           Fondus enchaînés, pauses, rognage des silences (streaming)
    Audio/AudioFileIO             Écriture fichier, rendu hors ligne AVAudioEngine (vitesse/hauteur/gain), export WAV/M4A
    Audio/AudioPlayerController   Lecteur AVAudioPlayer + forme d'onde
    Storage/ModelManager          Téléchargement / import / suppression des modèles
    Storage/ProjectRepository     Bibliothèque de projets (JSON + audio maître CAF 24 bits)
  UI/                             SwiftUI : Studio, Bibliothèque, Voix, Réglages, thème rose/noir/argent
  Resources/Assets.xcassets       Icône, couleur d'accent, fond de lancement
DianaVoiceStudioTests/            Tests unitaires et d'intégration (XCTest)
Vendor/OnnxRuntime/               Paquet Swift local ONNX Runtime 1.24.2 (liaisons Obj-C MIT + binaire NuGet)
scripts/setup.sh                  Installation d'ONNX Runtime (à lancer une fois avant Xcode)
scripts/download_models.sh        Téléchargement des modèles (embarquement / tests / import)
scripts/generate_app_icon.py      Génération de l'icône
.github/workflows/ios.yml         CI : compilation iPhone + tests sur simulateur avec le vrai modèle
```

Choix techniques notables :

- **Chargement paresseux** : les sessions ONNX ne sont créées qu'à la première synthèse, puis libérées
  en cas d'alerte mémoire.
- **Mémoire constante** : un seul segment audio en RAM ; tout le reste est écrit au fil de l'eau.
- **Vitesse naturelle** : de 0,7× à 2× la vitesse est produite par le modèle lui-même (prosodie naturelle) ;
  en dessous, un étirement temporel `AVAudioUnitTimePitch` complète. La hauteur utilise le même module
  (sans changer la durée).
- **Master sans perte** : chaque génération est conservée en CAF 24 bits, d'où des exports WAV/M4A
  instantanés et illimités sans regénérer.
- **Accélération Neural Engine** (option expérimentale dans Réglages) via le fournisseur Core ML d'ONNX Runtime.
- **MP3** : iOS ne fournit pas d'encodeur MP3 ; le format léger proposé est donc le **M4A/AAC**,
  de meilleure qualité à taille égale et lu partout (iPhone, Android, Windows, macOS, montage vidéo).

---

## Tests

Dans Xcode : **⌘U**. En ligne de commande :

```bash
xcodebuild test -project DianaVoiceStudio.xcodeproj -scheme DianaVoiceStudio \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Couverture :

- `TextSegmenterTests` : phrases, abréviations, décimales, guillemets français, ponctuation arabe,
  paragraphes, phrases très longues, mots sans espace et **script de plus de 50 000 caractères**
  (aucun mot perdu ni réordonné, aucun segment trop long).
- `TextProcessingTests` : normalisation, NFKD, émojis, balises de langue, jetons, catalogue des voix
  (FR/AR × femme/homme), lecture des styles vocaux, générateur aléatoire.
- `AudioAndProjectTests` : pauses, fondus enchaînés, absence de clics, rognage, réglages, bibliothèque.
- `EngineIntegrationTests` :
  - pipeline complet sur un script de 60 000 caractères avec un moteur factice (≈ 1 h d'audio en flux),
    vitesse 0,5×, hauteur, export WAV et M4A, annulation ;
  - **inférence réelle Supertonic 3** pour les 4 voix FR/AR femme/homme (ignorée si les modèles sont absents).
    Pour l'activer : `./scripts/download_models.sh "$PWD/.models"` puis
    `TEST_RUNNER_DIANA_MODELS_DIR="$PWD/.models" xcodebuild test …`.

La CI GitHub Actions (`.github/workflows/ios.yml`) compile l'app pour iPhone et exécute tous les tests,
y compris l'inférence réelle, à chaque push.

---

## Checklist de livraison

- [x] Projet Xcode complet (SwiftUI, iOS 18+, ONNX Runtime intégré localement via `scripts/setup.sh`).
- [x] Palette rose / noir / argent, modes clair et sombre, mise en page pensée pour le grand écran du 17 Pro Max.
- [x] Voix françaises féminines (5) et masculines (5).
- [x] Voix arabes féminines (5) et masculines (5).
- [x] Aucune limite de caractères — testé avec des scripts de plus de 50 000 caractères.
- [x] Téléchargement de l'audio sur l'iPhone en WAV et M4A (Fichiers + partage).
- [x] 100 % hors ligne (mode avion) après installation des voix — ou dès l'installation si elles sont embarquées.
- [x] Aucun compte, aucune clé API, aucun achat intégré.
- [x] README d'installation et d'utilisation.

---

## Studio en ligne aux voix naturelles (sans carte bancaire)

`docs/index.html` est le studio principal en ligne, publié avec **GitHub Pages** :
**https://dianahilali3-prog.github.io/StudioVoice/**

- Connexion avec un compte **Puter** gratuit (adresse e-mail, aucune carte bancaire, aucune clé API).
  Chaque compte reçoit un crédit gratuit mensuel ; l'app ajoute un quota quotidien réglable
  (10 000 caractères par défaut) pour le répartir sur le mois.
- **68 voix** : OpenAI gpt-4o-mini-tts (13), Google Gemini TTS (30), ElevenLabs multilingual v2 (14),
  xAI Grok (5) et Amazon Polly (Léa, Rémi, Gabrielle, Liam, Hala, Zayd). Toutes lisent le français et
  l'arabe, sauf Polly (une langue par voix, voix associée automatique pour l'autre langue).
- Styles de lecture (narration, conversation, storytelling, publicité, journal, calme, motivation ou
  consigne personnalisée) et accents (France, Québec, Belgique, arabe standard, marocain, égyptien,
  levantin, Golfe), transmis aux voix OpenAI et Gemini.
- Génération rapide : requêtes de 1 200 caractères envoyées 4 par 4 en parallèle.
- Vitesse et hauteur réglables, téléchargement direct en MP3, WAV et M4A, projets sauvegardés.

**Activer le site (une fois)** : GitHub › dépôt StudioVoice › *Settings* › *Pages* ›
*Build and deployment* › Source *Deploy from a branch* › branche `claude/diana-voice-studio-ios-4v4ay9`,
dossier `/docs` › *Save*. Le lien est actif une à deux minutes plus tard.

---

## Version web (aucune installation)

`web/index.html` est une version web de DianaVoiceStudio : mêmes 20 voix Supertonic 3, exécutées
**dans le navigateur** (ONNX Runtime Web, WebAssembly). Elle est publiée comme page claude.ai :
on ouvre le lien sur l'iPhone (Safari ou l'app Claude) et on utilise le studio directement.

- Premier lancement : téléchargement des voix (~198 Mo), ensuite gardées en cache dans le navigateur.
- Encodeur de texte et estimateur quantifiés en int8 (écart mesuré inférieur à la variation naturelle
  du modèle entre deux générations) ; vocodeur en float32.
- Export : WAV et MP3 (dans un `.zip`, seuls formats acceptés par le téléchargement de la page) et
  M4A/AAC en `.mp4` quand le navigateur sait encoder l'AAC.
- Projets sauvegardés dans le navigateur.
- Reconstruire les fichiers du modèle : `python3 scripts/build_web_models.py <dossier supertonic-3> <ort-wasm-simd-threaded.wasm> <sortie>`.

---

## Licences

- Code de l'application : utilisation libre pour le propriétaire du dépôt.
- **Supertonic 3** (modèle) : licence **OpenRAIL-M** de Supertone Inc. — usage libre, y compris commercial,
  sous réserve des restrictions d'usage de la licence (pas d'usurpation d'identité, pas de contenus trompeurs…).
- **ONNX Runtime** et ses liaisons Objective-C (`Vendor/OnnxRuntime`) : licence MIT (Microsoft).
