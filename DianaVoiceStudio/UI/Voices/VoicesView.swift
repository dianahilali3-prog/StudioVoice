import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Voice pack management (download once, then 100 % offline).
struct VoicesView: View {
    @Environment(AppModel.self) private var model
    @State private var showImporter = false
    @State private var confirmDelete = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    packCard
                    voicesCard(language: .french)
                    voicesCard(language: .arabic)
                    systemVoicesCard
                }
                .padding(16)
                .readableWidth()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Voix")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    do {
                        try model.models.importFolder(url)
                        importMessage = "Voix importées avec succès."
                    } catch {
                        importMessage = error.localizedDescription
                    }
                case .failure(let error):
                    importMessage = error.localizedDescription
                }
            }
            .confirmationDialog("Supprimer les voix neuronales ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer (\(model.models.installedSize.formattedBytes))", role: .destructive) {
                    model.models.delete()
                    model.clearPreviewCache()
                }
            } message: {
                Text("Vous pourrez les retélécharger à tout moment. Vos projets sont conservés.")
            }
            .onAppear { model.models.refresh() }
        }
    }

    private var packCard: some View {
        let manager = model.models
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(title: "Pack de voix neuronales", systemImage: "cpu")
                    Text("Supertonic 3")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("20 voix · Français & Arabe · Femmes & Hommes · 44,1 kHz · sur l'appareil")
                        .font(.subheadline)
                        .foregroundStyle(Theme.silver)
                }
                Spacer()
                stateBadge
            }

            switch manager.state {
            case .installed:
                Label(manager.isBundled ? "Inclus dans l'application." : "Installé · \(manager.installedSize.formattedBytes) · fonctionne en mode avion.",
                      systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.roseDeep)
                if !manager.isBundled {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Supprimer les voix", systemImage: "trash")
                    }
                    .buttonStyle(PillButtonStyle(tint: Theme.silver))
                }
            case .downloading:
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: manager.fraction)
                        .tint(Theme.rose)
                    HStack {
                        Text("\(manager.downloadedBytes.formattedBytes) / \(SupertonicModelFiles.totalApproximateBytes.formattedBytes)")
                        Spacer()
                        Text(manager.currentFile)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.silver)
                    Text("Gardez l'application ouverte pendant le téléchargement (Wi-Fi recommandé).")
                        .font(.caption)
                        .foregroundStyle(Theme.silver)
                    Button(role: .cancel) { manager.cancelDownload() } label: {
                        Label("Annuler", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.dvSecondary)
                }
            case .notInstalled, .failed:
                if case .failed(let message) = manager.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.roseDeep)
                }
                Text("Téléchargement unique et gratuit (~\(SupertonicModelFiles.totalApproximateBytes.formattedBytes)) depuis Hugging Face. Ensuite, plus aucune connexion n'est nécessaire : vos scripts ne quittent jamais l'iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                Button {
                    manager.download()
                } label: {
                    Label("Télécharger les voix", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.dvPrimary)
                Button {
                    showImporter = true
                } label: {
                    Label("Importer depuis Fichiers", systemImage: "folder")
                }
                .buttonStyle(.dvSecondary)
            }

            if let importMessage {
                Text(importMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
            }
        }
        .card()
        .onChange(of: manager.state) { _, state in
            UIApplication.shared.isIdleTimerDisabled = state == .downloading
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch model.models.state {
        case .installed: StatusChip(text: "Installé", systemImage: "checkmark")
        case .downloading: StatusChip(text: "\(Int(model.models.fraction * 100)) %", systemImage: "arrow.down")
        case .failed: StatusChip(text: "Erreur", systemImage: "exclamationmark.triangle")
        case .notInstalled: StatusChip(text: "À installer", systemImage: "icloud.and.arrow.down", tint: Theme.silver)
        }
    }

    private func voicesCard(language: VoiceLanguage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "\(language.flag) \(language.displayName)", systemImage: "person.2.wave.2")
            ForEach(VoiceGender.allCases) { gender in
                Text(gender == .female ? "Femmes" : "Hommes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.silver)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(VoiceCatalog.supertonicVoices.filter { $0.language == language && $0.gender == gender }) { voice in
                            voiceTile(voice)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .card()
    }

    private func voiceTile(_ voice: Voice) -> some View {
        let selected = model.project.voiceID == voice.id
        return VStack(spacing: 8) {
            VoiceAvatar(voice: voice, size: 52)
            Text(voice.persona)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
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
                .buttonStyle(CircleIconButtonStyle(size: 34))
                .accessibilityLabel("Écouter \(voice.persona)")
                Button {
                    withAnimation(.snappy) { model.project.voiceID = voice.id }
                } label: {
                    Image(systemName: selected ? "checkmark" : "plus")
                }
                .buttonStyle(CircleIconButtonStyle(size: 34, prominent: selected))
                .accessibilityLabel(selected ? "\(voice.persona) sélectionnée" : "Choisir \(voice.persona)")
            }
        }
        .padding(12)
        .frame(width: 112)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(selected ? Theme.roseMist : Theme.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(selected ? AnyShapeStyle(Theme.roseGradient) : AnyShapeStyle(Theme.silverLight), lineWidth: selected ? 2 : 1))
    }

    private var systemVoicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Voix système Apple", systemImage: "apple.logo")
            if model.appleVoices.isEmpty {
                Text("Aucune voix française ou arabe installée sur cet iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.silver)
            } else {
                ForEach(model.appleVoices) { voice in
                    HStack(spacing: 12) {
                        VoiceAvatar(voice: voice, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(voice.label).font(.subheadline.weight(.medium))
                            Text(voice.detail).font(.caption).foregroundStyle(Theme.silver).lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }
            Text("Disponibles sans téléchargement dans l'app. Ajoutez des voix « Améliorées » ou « Premium » dans Réglages › Accessibilité › Contenu énoncé › Voix.")
                .font(.caption)
                .foregroundStyle(Theme.silver)
        }
        .card()
    }
}
