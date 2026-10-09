import BabyCore
import SwiftUI

@main struct BabytrackApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) var delegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(Palette.accent).foregroundStyle(Palette.ink)
                .preferredColorScheme(store.appearance == "system" ? nil : store.appearance == "dark" ? .dark : .light)
                .task {
                    delegate.store = store; await store.prepareSignIn(); await store.sync(); await SleepCoordinator
                        .shared.observe(store: store)
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
