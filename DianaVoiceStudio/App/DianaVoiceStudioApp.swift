import SwiftUI

@main
struct DianaVoiceStudioApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.roseDeep)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.saveNow() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Studio", systemImage: "waveform", value: AppTab.studio) {
                StudioView()
            }
            Tab("Bibliothèque", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView()
            }
            Tab("Voix", systemImage: "person.wave.2", value: AppTab.voices) {
                VoicesView()
            }
            Tab("Réglages", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .alert("DianaVoiceStudio", isPresented: Binding(get: { model.alertMessage != nil },
                                                       set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .alert("Voix à installer", isPresented: $model.showModelRequiredAlert) {
            Button("Installer les voix") { model.selectedTab = .voices }
            Button("Plus tard", role: .cancel) {}
        } message: {
            Text("Cette voix neuronale nécessite un téléchargement unique (~\(SupertonicModelFiles.totalApproximateBytes.formattedBytes)). Vous pouvez aussi choisir une voix système Apple, disponible immédiatement.")
        }
    }
}
