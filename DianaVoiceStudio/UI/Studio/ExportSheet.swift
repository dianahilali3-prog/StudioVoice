import SwiftUI
import UniformTypeIdentifiers

/// Format choice + « Enregistrer dans Fichiers » / « Partager ».
struct ExportSheet: View {
    let project: VoiceProject
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .wav
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var showFileMover = false
    @State private var fileToMove: URL?
    @State private var message: String?
    @State private var savedToFiles = false

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionLabel(title: "Format", systemImage: "doc.badge.gearshape")
                    VStack(spacing: 10) {
                        ForEach(ExportFormat.allCases) { option in
                            formatRow(option)
                        }
                    }

                    if format == .wav {
                        Picker("Résolution WAV", selection: $settings.wavBitDepth) {
                            Text("16 bits").tag(16)
                            Text("24 bits").tag(24)
                            Text("32 bits float").tag(32)
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Picker("Débit AAC", selection: $settings.aacBitRate) {
                            Text("128 kb/s").tag(128_000)
                            Text("192 kb/s").tag(192_000)
                            Text("256 kb/s").tag(256_000)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(spacing: 12) {
                        Button {
                            Task { await export(thenShare: false) }
                        } label: {
                            Label("Enregistrer dans Fichiers", systemImage: "folder.fill.badge.plus")
                        }
                        .buttonStyle(.dvPrimary)

                        if let exportedURL {
                            ShareLink(item: exportedURL) {
                                Label("Partager…", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.dvSecondary)
                        } else {
                            Button {
                                Task { await export(thenShare: true) }
                            } label: {
                                Label("Préparer pour le partage", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.dvSecondary)
                        }
                    }
                    .disabled(isExporting)
                    .overlay {
                        if isExporting { ProgressView("Conversion…").tint(Theme.roseDeep).padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)) }
                    }

                    if let message {
                        Label(message, systemImage: savedToFiles ? "checkmark.circle.fill" : "info.circle")
                            .font(.footnote)
                            .foregroundStyle(savedToFiles ? Theme.roseDeep : Theme.silver)
                    }

                    Text("Une copie de chaque export est aussi conservée dans Fichiers › Sur mon iPhone › DianaVoiceStudio › Exports. Exports illimités.")
                        .font(.caption)
                        .foregroundStyle(Theme.silver)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Télécharger l'audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                        .tint(Theme.roseDeep)
                }
            }
            .fileMover(isPresented: $showFileMover, file: fileToMove) { result in
                switch result {
                case .success:
                    savedToFiles = true
                    message = "Fichier enregistré."
                case .failure(let error):
                    savedToFiles = false
                    message = error.localizedDescription
                }
            }
            .sensoryFeedback(.success, trigger: savedToFiles) { _, saved in saved && model.settings.hapticsEnabled }
        }
        .onAppear { format = model.settings.exportFormat }
        .onChange(of: format) { _, newValue in
            model.settings.exportFormat = newValue
            exportedURL = nil
        }
        .onChange(of: model.settings.wavBitDepth) { exportedURL = nil }
        .onChange(of: model.settings.aacBitRate) { exportedURL = nil }
    }

    private func formatRow(_ option: ExportFormat) -> some View {
        let selected = option == format
        let duration = project.audioDuration ?? 0
        let size = option.estimatedSize(duration: duration, wavBitDepth: model.settings.wavBitDepth, aacBitRate: model.settings.aacBitRate)
        return Button {
            withAnimation(.snappy) { format = option }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Theme.roseDeep : Theme.silver)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.silver)
                }
                Spacer()
                Text("≈ " + size.formattedBytes)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.silver)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? Theme.roseMist : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(Theme.roseGradient) : AnyShapeStyle(Theme.silverLight), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func export(thenShare: Bool) async {
        isExporting = true
        message = nil
        savedToFiles = false
        defer { isExporting = false }
        do {
            let url = try await model.export(format, project: project)
            exportedURL = url
            if thenShare {
                message = "Prêt : touchez « Partager… »."
            } else {
                // fileMover moves the file: give it a temporary copy, keep the original in Exports.
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: temp)
                try FileManager.default.copyItem(at: url, to: temp)
                fileToMove = temp
                showFileMover = true
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
