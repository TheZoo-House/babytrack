import AuthenticationServices
import BabyCore
import CryptoKit
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        @Bindable var store = store
        Group {
            if store.showWelcome {
                WelcomeView()
            } else if sizeClass == .regular {
                NavigationSplitView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            Image(systemName: "leaf.fill").foregroundStyle(Palette.accent); Text(store.branding)
                                .font(.title2.weight(.semibold))
                        }.padding(
                            .horizontal,
                            20
                        ).padding(.top, 20)
                        List { ForEach(AppSection.allCases) { section in
                            Button { store.selectedSection = section } label: { Label(
                                section.rawValue,
                                systemImage: section.symbol
                            ).foregroundStyle(store.selectedSection == section ? Palette.accent : Palette.ink) }
                                .accessibilityIdentifier("nav-\(section.rawValue)")
                                .listRowBackground(store.selectedSection == section ? Palette.accent
                                    .opacity(0.1) : Color.clear)
                        } }
                        .listStyle(.sidebar).scrollContentBackground(.hidden)
                        if store
                            .isPreview
                        {
                            Text("Sample family").font(.caption).foregroundStyle(.secondary).padding(20)
                        }
                    }.background(Palette.paper)
                } detail: {
                    NavigationStack { content(store.selectedSection) }.id(store.selectedSection)
                }.navigationSplitViewStyle(.balanced)
            } else {
                TabView(selection: $store.selectedSection) {
                    NavigationStack { TodayView() }.tabItem { Label("Today", systemImage: "sun.max") }
                        .tag(AppSection.today)
                    NavigationStack { LibraryView() }.tabItem { Label("Library", systemImage: "books.vertical") }
                        .tag(AppSection.library)
                    NavigationStack { HealthView() }.tabItem { Label("Health", systemImage: "heart") }
                        .tag(AppSection.health)
                    NavigationStack { MoreView() }.tabItem { Label("More", systemImage: "ellipsis") }
                        .tag(AppSection.settings)
                }
            }
        }
        .sheet(item: $store.form) { request in RecordForm(request: request) }
        .sheet(item: $store.detail) { entity in RecordDetail(entity: entity) }
        .alert(
            "Could not complete",
            isPresented: Binding(get: { store.error != nil }, set: {
                if !$0 {
                    store.error = nil
                }
            })
        ) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled {
                    await store.sync()
                }
            }
        }
    }

    @ViewBuilder private func content(_ section: AppSection) -> some View {
        switch section {
        case .today: TodayView()
        case .journal: JournalView()
        case .library: LibraryView()
        case .growth: GrowthView()
        case .health: HealthView()
        case .family: FamilyView()
        case .settings: SettingsView()
        }
    }
}

struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var loading = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Image(systemName: "leaf.fill").font(.system(size: 60, weight: .light)).foregroundStyle(Palette.accent)
                Text(store.branding).font(.system(.largeTitle, design: .rounded, weight: .bold))
                Spacer()
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                    if let nonce = store.nonce {
                        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(
                            format: "%02x",
                            $0
                        ) }.joined()
                    }
                } onCompletion: { result in
                    switch result {
                    case let .success(authorization):
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                              let data = credential.identityToken,
                              let token = String(data: data, encoding: .utf8)
                        else { store.error = "Apple did not return a sign-in credential."; return }
                        let name = credential.fullName.map { PersonNameComponentsFormatter().string(
                            from: $0
                        ) } ?? "Caregiver"
                        Task { await store.signIn(identityToken: token, name: name) }
                    case let .failure(error):
                        if (error as? ASAuthorizationError)?
                            .code != .canceled
                        {
                            store.error = error.localizedDescription
                        }
                    }
                }.signInWithAppleButtonStyle(scheme == .dark ? .white : .black).frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13)).disabled(store.nonce == nil)
                Button { loading = true; Task { await store.preview(); loading = false } } label: {
                    HStack {
                        Spacer(); if loading {
                            ProgressView()
                        } else {
                            Text("Try sample family").fontWeight(.semibold)
                        }; Spacer()
                    }.frame(height: 44)
                }.disabled(loading).accessibilityIdentifier("trySample")
                NavigationLink("Connection", destination: ConnectionView()).font(.subheadline)
                    .frame(maxWidth: .infinity)
            }.padding(32).frame(maxWidth: 500).frame(maxWidth: .infinity).background(Palette.paper)
        }
    }
}

struct MoreView: View {
    var body: some View {
        List {
            NavigationLink { JournalView() } label: { Label("Journal", systemImage: "clock") }
            NavigationLink { GrowthView() } label: { Label("Growth", systemImage: "chart.xyaxis.line") }
            NavigationLink { FamilyView() } label: { Label("Family", systemImage: "person.2") }
            NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(Palette.paper).navigationTitle("More")
    }
}
