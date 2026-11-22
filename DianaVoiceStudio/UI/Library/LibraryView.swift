import SwiftUI

/// Local history of projects (auto-saved).
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var exportProject: VoiceProject?
    @State private var pendingDeletion: VoiceProject?

    private var results: [VoiceProject] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.projects }
        return model.projects.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query) || $0.script.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.projects.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun projet", systemImage: "books.vertical")
                    } description: {
                        Text("Vos scripts sont enregistrés automatiquement ici dès que vous commencez à écrire.")
                    } actions: {
                        Button("Nouveau projet") { model.newProject() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.roseDeep)
                    }
                } else {
                    List {
                        ForEach(results) { project in
                            Button {
                                model.open(project)
                            } label: {
                                ProjectRow(project: project,
                                           voice: model.voice(withID: project.voiceID),
                                           isCurrent: project.id == model.project.id)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.surface)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDeletion = project
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    model.duplicate(project)
                                } label: {
                                    Label("Dupliquer", systemImage: "plus.square.on.square")
                                }
                                .tint(Theme.silver)
                            }
                            .contextMenu {
                                Button { model.open(project) } label: { Label("Ouvrir dans le Studio", systemImage: "waveform") }
                                if project.audioFileName != nil {
                                    Button { exportProject = project } label: { Label("Réexporter l'audio", systemImage: "arrow.down.circle") }
                                }
                                Button { model.duplicate(project) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
                                Button(role: .destructive) { pendingDeletion = project } label: { Label("Supprimer", systemImage: "trash") }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .searchable(text: $search, prompt: "Rechercher un script")
                    .overlay {
                        if results.isEmpty { ContentUnavailableView.search(text: search) }
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Bibliothèque")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.newProject() } label: { Label("Nouveau projet", systemImage: "square.and.pencil") }
                        .tint(Theme.roseDeep)
                        .disabled(model.generationState.isRunning)
                }
            }
            .sheet(item: $exportProject) { project in
                ExportSheet(project: project)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Supprimer ce projet ?",
                                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingDeletion) { project in
                Button("Supprimer « \(project.displayTitle) »", role: .destructive) {
                    model.delete([project.id])
                }
            } message: { _ in
                Text("Le script et son audio seront définitivement supprimés de l'iPhone.")
            }
        }
    }
}

private struct ProjectRow: View {
    let project: VoiceProject
    let voice: Voice
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VoiceAvatar(voice: voice, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(project.displayTitle)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if isCurrent {
                        Text("Ouvert")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.roseGradient))
                    }
                }
                Text(project.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(Theme.silver)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 10) {
                    Label(voice.shortLabel, systemImage: "person.wave.2")
                    if let duration = project.audioDuration, project.audioFileName != nil {
                        Label(ScriptStatistics.formatDuration(duration), systemImage: "waveform")
                    }
                    Spacer()
                    Text(project.updatedAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(Theme.silver)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
