import SwiftUI
import UIKit

struct StudioView: View {
    @Environment(AppModel.self) private var model
    @State private var showVoicePicker = false
    @State private var showExport = false
    @State private var showAdvanced = false
    @State private var insertRequest: ScriptEditor.InsertRequest?
    @FocusState private var titleFocused: Bool

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    voiceCard
                    scriptCard
                    ProsodyCard(settings: $model.project.settings, showAdvanced: $showAdvanced)
                    GenerateSection(showExport: $showExport)
                    if model.player.hasAudio {
                        PlayerCard(showExport: $showExport)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Text("100 % hors ligne · Aucun compte · Aucune limite")
                        .font(.footnote)
                        .foregroundStyle(Theme.silver)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .readableWidth()
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.player.hasAudio)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.newProject()
                    } label: {
                        Label("Nouveau projet", systemImage: "square.and.pencil")
                    }
                    .tint(Theme.roseDeep)
                    .disabled(model.generationState.isRunning)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .sheet(isPresented: $showVoicePicker) {
                VoicePickerSheet()
            }
            .sheet(isPresented: $showExport) {
                ExportSheet(project: model.project)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Wordmark(size: 30)
                Spacer()
                modelStatus
            }
            TextField("Titre du projet", text: $model.project.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .focused($titleFocused)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.silverLight, lineWidth: 1))
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch model.models.state {
        case .installed:
            StatusChip(text: "Hors ligne", systemImage: "airplane")
        case .downloading:
            StatusChip(text: "\(Int(model.models.fraction * 100)) %", systemImage: "arrow.down.circle")
        default:
            Button {
                model.selectedTab = .voices
            } label: {
                StatusChip(text: "Installer les voix", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Voice

    private var voiceCard: some View {
        let voice = model.selectedVoice
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Voix", systemImage: "waveform")
            HStack(spacing: 14) {
                VoiceAvatar(voice: voice, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(voice.persona)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(voice.shortLabel)
                        .font(.subheadline)
                        .foregroundStyle(Theme.roseDeep)
                    Text(voice.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.silver)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    model.togglePreview(voice)
                } label: {
                    previewIcon(for: voice)
                }
                .buttonStyle(CircleIconButtonStyle(size: 46))
                .accessibilityLabel("Écouter un extrait de \(voice.persona)")
            }
            Button {
                showVoicePicker = true
            } label: {
                Label("Choisir une voix", systemImage: "person.wave.2")
            }
            .buttonStyle(.dvSecondary)
            .disabled(model.generationState.isRunning)
        }
        .card()
    }

    @ViewBuilder
    private func previewIcon(for voice: Voice) -> some View {
        if model.loadingPreviewVoiceID == voice.id {
            ProgressView().tint(Theme.roseDeep)
        } else if model.previewingVoiceID == voice.id {
            Image(systemName: "stop.fill")
        } else {
            Image(systemName: "play.fill")
        }
    }

    // MARK: - Script

    private var scriptCard: some View {
        @Bindable var model = model
        let script = model.project.script
        let characters = script.count
        let words = ScriptStatistics.wordCount(script)
        let estimate = ScriptStatistics.estimatedDuration(characters: characters, speed: model.project.settings.speed)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: "Script", systemImage: "text.alignleft")
                Spacer()
                Menu {
                    Section("Balises expressives") {
                        Button("Rire  <laugh>") { insertRequest = .init(snippet: " <laugh> ") }
                        Button("Respiration  <breath>") { insertRequest = .init(snippet: " <breath> ") }
                        Button("Soupir  <sigh>") { insertRequest = .init(snippet: " <sigh> ") }
                    }
                    Section("Mise en forme") {
                        Button("Nouveau paragraphe (pause longue)") { insertRequest = .init(snippet: "\n") }
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.roseDeep)
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel("Insérer une balise")
            }

            ScriptEditor(text: $model.project.script,
                         placeholder: "Collez ou écrivez votre script ici… Aucune limite de longueur. Chaque retour à la ligne crée une pause plus longue.",
                         insertRequest: insertRequest)
                .frame(minHeight: 240, idealHeight: 340, maxHeight: 480)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surfaceRaised))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.silverLight, lineWidth: 1))
                .environment(\.layoutDirection, .leftToRight)

            HStack(spacing: 10) {
                Button {
                    if let pasted = UIPasteboard.general.string {
                        model.project.script = script.isEmpty ? pasted : script + "\n" + pasted
                    }
                } label: {
                    Label("Coller", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.dvPill)

                Button(role: .destructive) {
                    model.project.script = ""
                } label: {
                    Label("Effacer", systemImage: "xmark")
                }
                .buttonStyle(PillButtonStyle(tint: Theme.silver))
                .disabled(script.isEmpty)

                Spacer()
            }
            .disabled(model.generationState.isRunning)

            HStack(spacing: 14) {
                stat(value: characters.formatted(), label: "caractères")
                stat(value: words.formatted(), label: "mots")
                stat(value: "≈ " + ScriptStatistics.formatDuration(estimate), label: "durée")
            }
        }
        .card()
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.silver)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
