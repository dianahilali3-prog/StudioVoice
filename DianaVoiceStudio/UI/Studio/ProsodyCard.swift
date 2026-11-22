import SwiftUI

/// Speed, pitch, quality and assembly settings of the current project.
struct ProsodyCard: View {
    @Binding var settings: SynthesisSettings
    @Binding var showAdvanced: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionLabel(title: "Prosodie", systemImage: "slider.horizontal.3")

            ValueSlider(title: "Vitesse", systemImage: "gauge.with.dots.needle.50percent",
                        value: $settings.speed, range: SynthesisSettings.speedRange, step: 0.05,
                        defaultValue: 1.0,
                        format: { String(format: "%.2f×", $0) },
                        minLabel: "0,5×", maxLabel: "2×")

            ValueSlider(title: "Hauteur", systemImage: "music.note",
                        value: $settings.pitchSemitones, range: SynthesisSettings.pitchRange, step: 0.5,
                        defaultValue: 0,
                        format: { $0 == 0 ? "Naturelle" : String(format: "%+.1f demi-ton%@", $0, abs($0) >= 2 ? "s" : "") },
                        minLabel: "Plus grave", maxLabel: "Plus aiguë")

            VStack(alignment: .leading, spacing: 8) {
                Label("Qualité", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Picker("Qualité", selection: $settings.quality) {
                    ForEach(SynthesisQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                Text(qualityHint)
                    .font(.caption)
                    .foregroundStyle(Theme.silver)
            }

            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 16) {
                    ValueSlider(title: "Pause entre phrases", systemImage: "pause",
                                value: $settings.sentencePause, range: 0...1.5, step: 0.05, defaultValue: 0.30,
                                format: { String(format: "%.2f s", $0) })
                    ValueSlider(title: "Pause entre paragraphes", systemImage: "paragraphsign",
                                value: $settings.paragraphPause, range: 0...3, step: 0.1, defaultValue: 0.70,
                                format: { String(format: "%.1f s", $0) })
                    ValueSlider(title: "Fondu enchaîné", systemImage: "waveform.path",
                                value: $settings.crossfade, range: 0.005...0.08, step: 0.005, defaultValue: 0.02,
                                format: { String(format: "%.0f ms", $0 * 1000) })
                    Toggle(isOn: $settings.autoDetectLanguage) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Détection automatique FR / AR")
                                .font(.subheadline.weight(.semibold))
                            Text("Lit les passages arabes en arabe et les passages français en français, avec la même voix.")
                                .font(.caption)
                                .foregroundStyle(Theme.silver)
                        }
                    }
                    Toggle(isOn: $settings.normalizeLoudness) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Normaliser le volume")
                                .font(.subheadline.weight(.semibold))
                            Text("Niveau de crête à -1 dBFS, prêt pour le montage.")
                                .font(.caption)
                                .foregroundStyle(Theme.silver)
                        }
                    }
                    Button {
                        model.project.seed = UInt64.random(in: 1...UInt64.max)
                    } label: {
                        Label("Nouvelle interprétation", systemImage: "dice")
                    }
                    .buttonStyle(.dvPill)
                    Text("Chaque projet garde la même interprétation à chaque génération. Touchez ci-dessus pour en obtenir une nouvelle.")
                        .font(.caption)
                        .foregroundStyle(Theme.silver)
                }
                .tint(Theme.rose)
                .padding(.top, 12)
            } label: {
                Text("Réglages avancés")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.roseDeep)
        }
        .card()
        .disabled(model.generationState.isRunning)
    }

    private var qualityHint: String {
        switch settings.quality {
        case .fast: return "Génération la plus rapide, idéale pour les brouillons."
        case .balanced: return "Le meilleur compromis qualité / vitesse (recommandé)."
        case .high: return "Diction plus précise, génération ~1,5× plus longue."
        case .studio: return "Qualité maximale, génération ~2× plus longue."
        }
    }
}
