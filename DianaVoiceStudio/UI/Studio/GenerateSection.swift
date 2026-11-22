import SwiftUI

/// « Générer » button, live progress and errors.
struct GenerateSection: View {
    @Environment(AppModel.self) private var model
    @Binding var showExport: Bool

    var body: some View {
        VStack(spacing: 12) {
            switch model.generationState {
            case .running(let progress):
                runningView(progress)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .failed(let message):
                failureView(message)
                generateButton
            case .idle:
                generateButton
                if model.player.hasAudio && !model.project.isAudioUpToDate {
                    Label("Le script ou les réglages ont changé depuis la dernière génération.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.silver)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.generationState.isRunning)
        .sensoryFeedback(.success, trigger: model.completedGenerations) { _, _ in model.settings.hapticsEnabled }
    }

    private var generateButton: some View {
        Button {
            model.generate()
        } label: {
            Label(model.player.hasAudio ? "Générer à nouveau" : "Générer", systemImage: "waveform.badge.plus")
                .font(.title3.weight(.bold))
        }
        .buttonStyle(.dvPrimary)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.generationState.isRunning) { _, running in
            running && model.settings.hapticsEnabled
        }
        .accessibilityHint("Lance la synthèse vocale de tout le script")
    }

    private func runningView(_ progress: GenerationProgress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProgressRing(fraction: progress.fraction)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: progress))
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(subtitle(for: progress))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.silver)
                }
                Spacer()
            }
            ProgressView(value: progress.fraction)
                .tint(Theme.rose)
            Button(role: .cancel) {
                model.cancelGeneration()
            } label: {
                Label("Annuler", systemImage: "xmark.circle")
            }
            .buttonStyle(.dvSecondary)
        }
        .card()
    }

    private func title(for progress: GenerationProgress) -> String {
        switch progress.phase {
        case .preparing: return "Chargement de la voix…"
        case .synthesizing: return "Génération en cours · \(Int(progress.fraction * 100)) %"
        case .finishing: return "Finalisation du fichier audio…"
        }
    }

    private func subtitle(for progress: GenerationProgress) -> String {
        switch progress.phase {
        case .preparing:
            return "Premier chargement du modèle : quelques secondes."
        case .synthesizing:
            var parts = ["Segment \(progress.completedSegments)/\(progress.totalSegments)",
                         "audio \(ScriptStatistics.formatDuration(progress.audioSeconds))"]
            if let remaining = progress.estimatedRemaining, progress.completedSegments > 0 {
                parts.append("reste ≈ \(ScriptStatistics.formatDuration(remaining))")
            }
            return parts.joined(separator: " · ")
        case .finishing:
            return "Vitesse, hauteur et volume appliqués."
        }
    }

    private func failureView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.roseDeep)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                model.dismissGenerationError()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.silver)
            }
            .buttonStyle(.plain)
        }
        .card(padding: 14)
    }
}

struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.silverLight, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(Theme.roseGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.roseDeep)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        }
    }
}

/// Player: waveform, transport controls and download.
struct PlayerCard: View {
    @Environment(AppModel.self) private var model
    @Binding var showExport: Bool

    var body: some View {
        let player = model.player
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionLabel(title: "Écouter", systemImage: "headphones")
                Spacer()
                if let duration = model.project.audioDuration {
                    Text(ScriptStatistics.formatDuration(duration))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.silver)
                }
            }

            WaveformView(peaks: player.waveform, progress: player.progress) { fraction in
                player.seek(toFraction: fraction)
            }
            .frame(height: 64)

            HStack {
                Text(ScriptStatistics.formatDuration(player.currentTime))
                Spacer()
                Text("-" + ScriptStatistics.formatDuration(max(0, player.duration - player.currentTime)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.silver)

            HStack(spacing: 26) {
                Spacer()
                Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                    .buttonStyle(CircleIconButtonStyle(size: 52))
                    .accessibilityLabel("Reculer de 10 secondes")
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(CircleIconButtonStyle(size: 74, prominent: true))
                .accessibilityLabel(player.isPlaying ? "Pause" : "Écouter")
                .sensoryFeedback(.selection, trigger: player.isPlaying) { _, _ in model.settings.hapticsEnabled }
                Button { player.skip(by: 10) } label: { Image(systemName: "goforward.10") }
                    .buttonStyle(CircleIconButtonStyle(size: 52))
                    .accessibilityLabel("Avancer de 10 secondes")
                Spacer()
            }

            Button {
                player.pause()
                showExport = true
            } label: {
                Label("Télécharger", systemImage: "arrow.down.circle.fill")
                    .font(.title3.weight(.bold))
            }
            .buttonStyle(.dvPrimary)
            .disabled(model.generationState.isRunning)
        }
        .card()
    }
}
