import SwiftUI

@MainActor final class AppModel: ObservableObject {
    @Published var credentials = Credentials(server: "", user: "", password: "")
    @Published var connected = false
    @Published var busy = false
    @Published var error: String?
    @Published var catalogs: [MediaKind: Catalog] = [:]
    @Published var data = ViewingData()
    @Published var playing: Media?
    private var started = false
    var api: Xtream { Xtream(credentials: credentials) }
    private var storageKey: String { "viewing." + credentials.account }
    func start() async { guard !started else { return }; started = true; if let saved = Vault.read() { credentials = saved; await login() } }
    func login() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            credentials = try credentials.validated(); try await api.login()
            try Vault.save(credentials)
            data = UserDefaults.standard.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(ViewingData.self, from: $0) } ?? ViewingData()
            connected = true; error = nil
        } catch let e as AppError { error = e.localizedDescription } catch { self.error = "Falha na conexão ou ao salvar o acesso com segurança. Confira os dados e tente novamente." }
    }
    func load(_ kind: MediaKind) async {
        guard catalogs[kind] == nil, !busy else { return }; busy = true; defer { busy = false }
        do { catalogs[kind] = try await api.catalog(kind) } catch { self.error = "Não foi possível carregar a lista. Volte e tente novamente." }
    }
    func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var next: [MediaKind: Catalog] = [:]
            for kind in MediaKind.allCases { next[kind] = try await api.catalog(kind) }
            catalogs = next
        } catch { self.error = "Atualização não concluída. As listas anteriores foram preservadas." }
    }
    func persist() { if let raw = try? JSONEncoder().encode(data) { UserDefaults.standard.set(raw, forKey: storageKey) } }
    func favorite(_ media: Media) {
        if data.favorites.contains(where: { $0.id == media.id }) { data.favorites.removeAll { $0.id == media.id } }
        else { data.favorites.insert(media, at: 0) }
        persist()
    }
    func play(_ media: Media) {
        data.recent.removeAll { $0.id == media.id }; data.recent.insert(media, at: 0); data.recent = Array(data.recent.prefix(60))
        persist(); playing = media
    }
    func save(_ media: Media, position: Double, duration: Double, ended: Bool = false) {
        guard media.kind != .live, position.isFinite, position >= 0 else { return }
        data.progress[media.id] = ended || (duration.isFinite && duration > 0 && position >= duration - 10) ? nil : position
        persist()
    }
    func logout() { playing = nil; Vault.clear(); connected = false; credentials = Credentials(server: "", user: "", password: ""); catalogs = [:]; data = ViewingData() }
    func erase() { for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("viewing.") { UserDefaults.standard.removeObject(forKey: key) }; logout() }
}

@main @MainActor struct GIPTVApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).preferredColorScheme(.dark).tint(.cyan)
        }
    }
}
@MainActor struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Group { if model.connected { HomeView() } else { LoginView() } }
            .task { await model.start() }
            .alert("GIPTV", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
            .fullScreenCover(item: $model.playing) { media in PlaybackView(media: media, model: model) }
    }
}
@MainActor struct LoginView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationStack {
            Form {
                Section { Label("GIPTV", systemImage: "play.circle.fill").font(.largeTitle).foregroundStyle(.cyan); Text("Seu conteúdo, no iPhone.") }
                Section("Acesso ao seu serviço") {
                    TextField("Servidor HTTP ou HTTPS", text: $model.credentials.server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.busy)
                    TextField("Usuário", text: $model.credentials.user).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.busy)
                    SecureField("Senha", text: $model.credentials.password).disabled(model.busy)
                    Button { Task { await model.login() } } label: { HStack { Text("Conectar"); if model.busy { Spacer(); ProgressView() } } }.disabled(model.busy)
                }
                Section { Text("Use apenas serviços e conteúdos autorizados. Conexões HTTP não cifram os dados; prefira HTTPS quando disponível.").font(.footnote) }
            }
        }
    }
}
@MainActor struct HomeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(MediaKind.allCases) { kind in
                        NavigationLink { CatalogView(kind: kind) } label: {
                            HStack { Image(systemName: kind.icon).font(.largeTitle); Text(kind.title).font(.title2.bold()); Spacer(); Image(systemName: "chevron.right") }
                                .padding(24).background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    NavigationLink("Últimos abertos") { RecentView() }.buttonStyle(.bordered)
                    Button("Atualizar lista inteira") { Task { await model.refresh() } }.disabled(model.busy)
                    if model.busy { ProgressView("Atualizando…") }
                    NavigationLink("Privacidade e opções") { SettingsView() }
                }.padding()
            }.navigationTitle("GIPTV")
        }
    }
}
@MainActor struct CatalogView: View {
    @EnvironmentObject var model: AppModel
    let kind: MediaKind
    @State private var search = ""
    @State private var category = ""
    @State private var mode = "Todos"
    var entries: [Media] {
        let base = mode == "Favoritos" ? model.data.favorites.filter { $0.kind == kind } : model.catalogs[kind]?.entries ?? []
        let result = base.filter { (category.isEmpty || $0.category == category) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) && (mode != "Novidades" || $0.added > 0) }
        return mode == "Novidades" ? result.sorted { $0.added > $1.added } : result
    }
    var body: some View {
        VStack {
            Picker("Mostrar", selection: $mode) { ForEach(["Todos", "Favoritos", "Novidades"], id: \.self) { Text($0) } }.pickerStyle(.segmented).padding(.horizontal)
            Picker("Categoria", selection: $category) {
                Text("Todas as categorias").tag("")
                ForEach(model.catalogs[kind]?.categories ?? []) { Text($0.title).tag($0.id) }
            }
            if model.busy { ProgressView("Carregando…") }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 14) {
                    ForEach(entries) { media in
                        if media.kind == .series && media.episode == nil { NavigationLink { EpisodesView(series: media) } label: { MediaTile(media: media) } }
                        else { Button { model.play(media) } label: { MediaTile(media: media) } }
                    }
                }.padding()
                if entries.isEmpty && !model.busy { Text("Nenhum conteúdo nesta lista.").foregroundStyle(.secondary) }
            }
        }.navigationTitle(kind.title).searchable(text: $search, prompt: "Buscar")
            .task { await model.load(kind) }
    }
}
@MainActor struct MediaTile: View {
    @EnvironmentObject var model: AppModel
    let media: Media
    var isFavorite: Bool { model.data.favorites.contains { $0.id == media.id } }
    var body: some View {
        VStack(spacing: 6) {
            AsyncImage(url: URL(string: media.image)) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: media.kind.icon).font(.largeTitle).foregroundStyle(.cyan) }
                .frame(height: 86).frame(maxWidth: .infinity).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
            Text((isFavorite ? "★ " : "") + media.title).font(.caption).lineLimit(2).frame(height: 34)
        }.foregroundStyle(.white)
            .onLongPressGesture { model.favorite(media) }
            .accessibilityAction(named: isFavorite ? "Remover dos favoritos" : "Favoritar") { model.favorite(media) }
    }
}
@MainActor struct EpisodesView: View {
    @EnvironmentObject var model: AppModel
    let series: Media
    @State private var episodes: [Media] = []
    @State private var season = 0
    @State private var loading = true
    @State private var failure = ""
    var seasons: [Int] { Array(Set(episodes.compactMap(\.season))).sorted() }
    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(seasons, id: \.self) { n in Button(n == 0 ? "Especiais" : "Temporada \(n)") { season = n }.buttonStyle(.bordered).tint(n == season ? .cyan : .gray) } }.padding(.horizontal)
            }
            if loading { ProgressView("Carregando temporadas…") }
            if !failure.isEmpty { Text(failure) }
            List(episodes.filter { $0.season == season }) { media in
                Button(media.title) { model.play(media) }
                    .swipeActions { Button("Favorito") { model.favorite(media) }.tint(.cyan) }
            }
        }.navigationTitle(series.title)
            .task { do { episodes = try await model.api.episodes(series); season = seasons.first ?? 0 } catch { failure = "Não foi possível carregar os episódios." }; loading = false }
    }
}
@MainActor struct RecentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        List { ForEach(model.data.recent) { media in Button(media.title) { model.play(media) } } }
            .navigationTitle("Últimos abertos")
            .toolbar { Button("Limpar") { model.data.recent = []; model.persist() } }
    }
}
@MainActor struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var erase = false
    var body: some View {
        Form {
            Text("O GIPTV não fornece canais nem assinaturas. As credenciais são protegidas no Keychain. Favoritos, recentes e posições ficam neste iPhone, separados por conta. Não há publicidade ou analytics. O servidor escolhido recebe as requisições e seu IP. HTTP não cifra os dados.")
            Text("Esta versão usa o player nativo da Apple. TV ao vivo usa HLS; outros formatos e codecs dependem do serviço. Não há sincronização com Android ou Windows.")
            Button("Sair da conta") { model.logout() }.disabled(model.busy)
            Button("Apagar dados locais", role: .destructive) { erase = true }.disabled(model.busy)
        }.navigationTitle("Privacidade")
            .confirmationDialog("Apagar todos os dados locais do GIPTV?", isPresented: $erase) { Button("Apagar", role: .destructive) { model.erase() } }
    }
}
