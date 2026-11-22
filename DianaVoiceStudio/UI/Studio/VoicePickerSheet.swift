import SwiftUI

/// Visual voice list with language / gender filters and previews.
struct VoicePickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var language: VoiceLanguage?
    @State private var gender: VoiceGender?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filters
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }

                if model.models.state != .installed {
                    Section {
                        modelBanner
                    }
                    .listRowBackground(Theme.roseMist)
                }

                ForEach(VoiceLanguage.allCases.filter { language == nil || $0 == language }) { lang in
                    let voices = filtered(VoiceCatalog.supertonicVoices, language: lang)
                    if !voices.isEmpty {
                        Section {
                            ForEach(voices) { voice in row(voice) }
                        } header: {
                            Text("\(lang.flag) \(lang.displayName) · Voix neuronales")
                        }
                    }
                }

                let system = filtered(model.appleVoices, language: language)
                if !system.isEmpty {
                    Section {
                        ForEach(system) { voice in row(voice) }
                    } header: {
                        Text("Voix système Apple")
                    } footer: {
                        Text("Utilisables immédiatement, hors ligne. Pour plus de voix : Réglages › Accessibilité › Contenu énoncé › Voix.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Choisir une voix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(Theme.roseDeep)
                }
            }
            .onAppear {
                language = model.selectedVoice.language
                model.refreshSystemVoices()
            }
            .onDisappear { model.stopPreview() }
        }
        .presentationDragIndicator(.visible)
    }

    private var filters: some View {
        VStack(spacing: 10) {
            Picker("Langue", selection: $language) {
                Text("Toutes").tag(VoiceLanguage?.none)
                ForEach(VoiceLanguage.allCases) { lang in
                    Text("\(lang.flag) \(lang.displayName)").tag(VoiceLanguage?.some(lang))
                }
            }
            .pickerStyle(.segmented)
            Picker("Genre", selection: $gender) {
                Text("Tous").tag(VoiceGender?.none)
                ForEach(VoiceGender.allCases) { g in
                    Text(g.displayName).tag(VoiceGender?.some(g))
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var modelBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.roseDeep)
            VStack(alignment: .leading, spacing: 3) {
                Text("Voix neuronales à installer")
                    .font(.subheadline.weight(.semibold))
                Text("Un seul téléchargement (~\(SupertonicModelFiles.totalApproximateBytes.formattedBytes)) puis tout fonctionne en mode avion.")
                    .font(.caption)
                    .foregroundStyle(Theme.silver)
            }
            Spacer()
            Button("Installer") {
                dismiss()
                model.selectedTab = .voices
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.roseDeep)
        }
    }

    private func filtered(_ voices: [Voice], language: VoiceLanguage?) -> [Voice] {
        voices.filter { (language == nil || $0.language == language) && (gender == nil || $0.gender == gender) }
    }

    private func row(_ voice: Voice) -> some View {
        let selected = voice.id == model.project.voiceID
        let available = model.isAvailable(voice)
        return HStack(spacing: 14) {
            VoiceAvatar(voice: voice, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(available ? voice.detail : "À télécharger")
                    .font(.caption)
                    .foregroundStyle(Theme.silver)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                model.togglePreview(voice)
            } label: {
                Group {
                    if model.loadingPreviewVoiceID == voice.id {
                        ProgressView().tint(Theme.roseDeep)
                    } else {
                        Image(systemName: model.previewingVoiceID == voice.id ? "stop.fill" : "play.fill")
                    }
                }
            }
            .buttonStyle(CircleIconButtonStyle(size: 40))
            .accessibilityLabel("Écouter un extrait de \(voice.persona)")
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(selected ? Theme.roseDeep : Theme.silverLight)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) { model.project.voiceID = voice.id }
        }
        .listRowBackground(selected ? Theme.roseMist : Theme.surface)
        .sensoryFeedback(.selection, trigger: selected) { _, isSelected in isSelected && model.settings.hapticsEnabled }
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
