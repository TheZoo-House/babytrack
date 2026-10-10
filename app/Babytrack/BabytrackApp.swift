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
                    if let link = DeepLink(url: url) { store.handle(link) }
                }
        }
    }
}
