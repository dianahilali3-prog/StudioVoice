import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var storageInfo = ""
    @State private var confirmClear = false

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section {
                    Picker("Format par défaut", selection: $settings.exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Résolution WAV", selection: $settings.wavBitDepth) {
                        Text("16 bits (CD)").tag(16)
                        Text("24 bits (studio)").tag(24)
                        Text("32 bits float").tag(32)
                    }
                    Picker("Débit M4A", selection: $settings.aacBitRate) {
                        Text("128 kb/s").tag(128_000)
                        Text("192 kb/s").tag(192_000)
                        Text("256 kb/s").tag(256_000)
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Tous les fichiers sont en 44,1 kHz mono. Exports illimités.")
                }

                Section {
                    Picker("Qualité des nouveaux projets", selection: $settings.defaultSynthesis.quality) {
                        ForEach(SynthesisQuality.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Détection automatique FR / AR", isOn: $settings.defaultSynthesis.autoDetectLanguage)
                    Toggle("Normaliser le volume", isOn: $settings.defaultSynthesis.normalizeLoudness)
                    Toggle(isOn: $settings.useNeuralEngine) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accélération Neural Engine")
                            Text("Expérimental : utilise Core ML. Désactivez en cas de problème.")
                                .font(.caption)
                                .foregroundStyle(Theme.silver)
                        }
                    }
                    Button("Appliquer au projet ouvert") {
                        model.project.settings.quality = settings.defaultSynthesis.quality
                        model.project.settings.autoDetectLanguage = settings.defaultSynthesis.autoDetectLanguage
                        model.project.settings.normalizeLoudness = settings.defaultSynthesis.normalizeLoudness
                    }
                    .tint(Theme.roseDeep)
                } header: {
                    Text("Génération")
                }

                Section {
                    Toggle("Retour haptique", isOn: $settings.hapticsEnabled)
                } header: {
                    Text("Interface")
                }

                Section {
                    LabeledContent("Projets et audio", value: storageInfo)
                    LabeledContent("Voix neuronales", value: model.models.installedSize.formattedBytes)
                    Button("Vider le cache des extraits", role: .destructive) { confirmClear = true }
                } header: {
                    Text("Stockage")
                }

                Section {
                    privacyRow("airplane", "Fonctionne en mode avion une fois les voix installées.")
                    privacyRow("lock.shield", "Vos scripts ne quittent jamais l'iPhone : aucune donnée envoyée.")
                    privacyRow("person.crop.circle.badge.xmark", "Aucun compte, aucune clé API, aucun abonnement.")
                    privacyRow("infinity", "Aucune limite de caractères, de générations ni de téléchargements.")
                } header: {
                    Text("Confidentialité")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Moteur vocal", value: "Supertonic 3 (ONNX Runtime)")
                    Link("Licence du modèle (OpenRAIL-M)", destination: URL(string: "https://huggingface.co/Supertone/supertonic-3/blob/main/LICENSE")!)
                    Link("ONNX Runtime (MIT)", destination: URL(string: "https://onnxruntime.ai")!)
                } header: {
                    Text("À propos")
                } footer: {
                    Text("DianaVoiceStudio · fait avec 🩷 · gratuit et sans limites.")
                }
            }
            .tint(Theme.roseDeep)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Réglages")
            .task { await refreshStorage() }
            .confirmationDialog("Vider le cache ?", isPresented: $confirmClear) {
                Button("Vider", role: .destructive) { model.clearPreviewCache() }
            }
        }
    }

    private func privacyRow(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.roseDeep)
        }
    }

    private func refreshStorage() async {
        let repository = model.repository
        let size = await Task.detached { repository.totalSize() }.value
        storageInfo = size.formattedBytes
    }
}
