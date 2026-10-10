import AppIntents
import BabyCore
import Combine
import SwiftUI

@main struct BabytrackApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) var delegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    init() {
        Palette.configureNavigation()
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(Palette.accent).foregroundStyle(Palette.ink)
                .preferredColorScheme(store.appearance == "system" ? nil : store.appearance == "dark" ? .dark : .light)
                .task {
                    BabytrackShortcuts.updateAppShortcutParameters(); delegate.store = store; await store.prepareSignIn(); await store.sync(); await SleepCoordinator
                        .shared.observe(store: store)
                }
                .onReceive(NotificationCenter.default.publisher(for: SharedStorage.didChange).receive(on: RunLoop.main)) { _ in
                    store.reload(); Task {
                        if store.pendingCount > 0 {
                            await store.sync()
                        }; await SleepCoordinator.shared.reconcile(store: store)
                    }
                }
                .onChange(of: phase) { _, phase in
                    if phase ==
                        .active
                    {
                        store
                            .reload(); Task { await store.sync(); await SleepCoordinator.shared.reconcile(store: store)
                            }
                    }
                }
                .onOpenURL { url in
                    if url.host == "sleep",
                       let sessionID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                       .first(where: { $0.name == "session" })?.value
                    {
                        Task { await store.endSleep(sessionID) }
                    } else if url.host == "feeding" {
                        store.form = FormRequest(type: "feeding")
                    } else if url.host == "diaper" {
                        store.form = FormRequest(type: "diaper")
                    } else if url.host == "record",
                              let type = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "type" })?.value,
                              Catalog.shared.types.contains(where: { $0.id == type && !["formula", "child"].contains(type) })
                    {
                        store.form = FormRequest(type: type)
                    } else if url.host == "join",
                              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                              .first(where: { $0.name == "code" })?.value
                    {
                        Task { do { try await store.join(code) } catch { store.error = error.localizedDescription } }
                    }
                }
        }
    }
}
