import SwiftUI
import WebKit

@main
struct PTOApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.loggedIn { RootTabs() } else { LoginView() }
            }
            .environmentObject(store)
            .tint(.pto)
            .onChange(of: phase) { p in
                if p == .active && store.loggedIn { store.start() } else if p == .background { store.stop() }
            }
            .onAppear { if store.loggedIn { store.start() } }
        }
    }
}

// MARK: - Вкладки: на iPhone — внизу, на iPad — боковая панель

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, requests, schemes, journal, more
    var id: String { rawValue }
    var title: String {
        switch self { case .home: return "Главная"; case .requests: return "Заявки"; case .schemes: return "Схемы"; case .journal: return "Журнал"; case .more: return "Ещё" }
    }
    var icon: String {
        switch self { case .home: return "house"; case .requests: return "shippingbox"; case .schemes: return "square.stack.3d.up"; case .journal: return "list.bullet.clipboard"; case .more: return "ellipsis.circle" }
    }
}

struct RootTabs: View {
    @EnvironmentObject var store: Store
    @Environment(\.horizontalSizeClass) private var size
    @State private var tab: AppTab = .home

    var body: some View {
        if size == .regular {
            NavigationSplitView {
                List(AppTab.allCases, selection: Binding<AppTab?>(get: { tab }, set: { if let v = $0 { tab = v } })) { s in
                    Label(s.title, systemImage: s.icon).tag(s)
                }
                .navigationTitle("ПТО-центр")
                .safeAreaInset(edge: .bottom) { ProfileCard().padding() }
            } detail: {
                screen(tab)
            }
        } else {
            TabView(selection: $tab) {
                ForEach(AppTab.allCases) { s in
                    screen(s).tabItem { Label(s.title, systemImage: s.icon) }.tag(s)
                }
            }
        }
    }

    @ViewBuilder private func screen(_ s: AppTab) -> some View {
        switch s {
        case .home: HomeView(go: { tab = $0 })
        case .requests: RequestsView()
        case .schemes: SchemesView()
        case .journal: JournalView()
        case .more: MoreView()
        }
    }
}

// MARK: - Вход

struct LoginView: View {
    @EnvironmentObject var store: Store
    @State private var user = ""
    @State private var pass = ""
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("Logo").resizable().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.pto.opacity(0.35), radius: 16, y: 8)
            VStack(spacing: 6) {
                Text("ПТО-центр").font(.largeTitle.bold())
                Text("Заявки, исполнительные схемы и журнал прораба").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                TextField("Логин", text: $user).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Пароль", text: $pass).textContentType(.password).onSubmit(go)
            }
            .textFieldStyle(.roundedBorder).frame(maxWidth: 360)
            if let err { Text(err).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
            Button(action: go) {
                HStack { if busy { ProgressView().tint(.white) }; Text("Войти").bold() }.frame(maxWidth: 360, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).disabled(busy || user.isEmpty || pass.isEmpty)
            Spacer()
            Text("Тот же логин, что в ПТО-центре в браузере").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func go() {
        guard !user.isEmpty, !pass.isEmpty else { return }
        busy = true; err = nil
        Task {
            do { try await store.login(user, pass); store.start() } catch { err = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: - Главная

struct HomeView: View {
    @EnvironmentObject var store: Store
    let go: (AppTab) -> Void
    @State private var newReq: Rec?
    @State private var newShift = false

    private var name: String { let n = store.kv("name").str; return n.isEmpty ? "Инженер" : (n.components(separatedBy: " ").first ?? n) }
    private var monthReq: Int { let m = String(Fmt.today.prefix(7)); return store.list("requests").filter { $0["date"].str.hasPrefix(m) }.count }
    private var meters30: Double {
        let from = Fmt.iso.string(from: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        return store.list("journal").filter { $0["date"].str >= from }.reduce(0) { $0 + ($1["m"].num ?? 0) }
    }
    private var openIssues: Int { store.list("issues").filter { !["Закрыто", "Устранено"].contains($0["status"].str) }.count }
    private var workClosings: [Rec] { store.list("closings").filter { $0["status"].str == "work" }.sorted { ($0["no"].num ?? 0) > ($1["no"].num ?? 0) } }
    private var todayTasks: [Rec] { store.list("tasks").filter { !($0["done"]?.bool ?? false) && !$0["due"].str.isEmpty && $0["due"].str <= Fmt.today } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Fmt.ruLong.string(from: Date()).capitalized).font(.subheadline).foregroundStyle(.secondary)
                        Text("Добрый день, \(name)").font(.title2.bold())
                    }
                    HStack(spacing: 10) {
                        Button { newReq = RequestsView.blank(store, sec: nil) } label: { Label("Новая заявка", systemImage: "plus") }.buttonStyle(.borderedProminent)
                        Button { newShift = true } label: { Label("Записать смену", systemImage: "square.and.pencil") }.buttonStyle(.bordered)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        Tile(value: Fmt.num(meters30, 1) + " м", label: "смонтировано за 30 дней", icon: "ruler") { go(.journal) }
                        Tile(value: "\(monthReq)", label: "заявок за месяц", icon: "shippingbox") { go(.requests) }
                        Tile(value: "\(workClosings.count)", label: "закрытий в работе", icon: "square.stack.3d.up") { go(.schemes) }
                        Tile(value: "\(openIssues)", label: "открытых замечаний", icon: "exclamationmark.triangle", tint: openIssues > 0 ? .orange : .secondary) { go(.more) }
                    }
                    if !todayTasks.isEmpty {
                        Card(title: "Сегодня") {
                            ForEach(Array(todayTasks.prefix(6))) { t in
                                HStack {
                                    Text(t["text"].str).lineLimit(2)
                                    Spacer()
                                    Badge(text: t["due"].str < Fmt.today ? "просрочено" : "сегодня", color: t["due"].str < Fmt.today ? .red : .orange)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    if let c = workClosings.first {
                        let s = store.list("schemes").filter { $0["closing"].str == c.id }
                        let signed = s.filter { $0["status"].str == "signed" }.count
                        Button { go(.schemes) } label: {
                            Card(title: "В работе: закрытие №\(c["no"].str)") {
                                ProgressView(value: Double(signed), total: Double(max(1, s.count)))
                                Text("подписано \(signed) из \(s.count) схем").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(Pressable()).foregroundStyle(.primary)
                    }
                    SyncPill().frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
                }
                .padding()
            }
            .refreshable { await store.sync() }
            .navigationTitle("ПТО-центр")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $newReq) { r in NavigationStack { RequestEditView(rec: r, isNew: true) } }
            .sheet(isPresented: $newShift) { NavigationStack { NewShiftView() } }
        }
    }
}

struct Tile: View {
    let value: String, label: String, icon: String
    var tint: Color = .pto
    let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(tint)
                Text(value).font(.title2.bold()).monospacedDigit().foregroundStyle(.primary)
                Text(label).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Pressable())
    }
}

struct Card<C: View>: View {
    let title: String
    @ViewBuilder let content: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Нажатие ощущается: карточка слегка сжимается и пружинит обратно
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Профиль в углу

struct ProfileCard: View {
    @EnvironmentObject var store: Store
    @State private var edit = false
    private var name: String { let n = store.kv("name").str; return n.isEmpty ? "Инженер ПТО" : n }
    private var post: String { let p = store.cfg["post"].str; return p.isEmpty ? "Инженер ПТО" : p }
    private var initials: String { name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased() }
    var body: some View {
        Button { edit = true } label: {
            HStack(spacing: 10) {
                Text(initials).font(.subheadline.bold()).foregroundStyle(.white).frame(width: 36, height: 36)
                    .background(LinearGradient(colors: [.pto, Color.pto.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                    Text(post).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(Pressable())
        .sheet(isPresented: $edit) { ProfileEdit() }
    }
}

struct ProfileEdit: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var post = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Имя и фамилия", text: $name).textContentType(.name)
                TextField("Должность", text: $post)
            }
            .navigationTitle("Профиль").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        store.setKV("name", .s(name.trimmingCharacters(in: .whitespaces)))
                        var c = store.cfg
                        c["post"] = .s(post.trimmingCharacters(in: .whitespaces))
                        store.setKV("cfg", c)
                        dismiss()
                    }
                }
            }
            .onAppear { name = store.kv("name").str; post = store.cfg["post"].str.isEmpty ? "Инженер ПТО" : store.cfg["post"].str }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Ещё: профиль, синхронизация, остальные разделы

struct MoreView: View {
    @EnvironmentObject var store: Store
    @State private var askLogout = false
    @State private var cacheMB = FileCache.sizeMB
    private let web: [(String, String, String)] = [
        ("Замечания", "iss", "exclamationmark.triangle"), ("Стыки", "joint", "flame"), ("Материалы", "mat", "cube.box"),
        ("Сводка заявок", "reqdash", "chart.bar"), ("КС-2 и КС-3", "is", "doc.text"), ("Калькуляторы", "calc", "function"),
        ("Сортамент труб", "pipe", "circle.circle"), ("Расчётные листы", "sheets", "tablecells"), ("Контакты", "contacts", "person.2"),
        ("Нормативка", "norm", "books.vertical"), ("Шпаргалки ПТО", "cheat", "lightbulb"), ("Задачи", "task", "checklist"),
        ("Заметки", "note", "note.text"), ("Табель", "tab", "calendar"), ("Настройки и темы", "set", "gearshape")]

    var body: some View {
        NavigationStack {
            List {
                Section { ProfileCard().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                Section("Синхронизация") {
                    SyncPill()
                    if let d = store.lastSync { LabeledContent("Последняя", value: d.formatted(date: .omitted, time: .shortened)) }
                    Button("Обновить сейчас") { Task { await store.sync() } }
                }
                Section("Другие разделы") {
                    ForEach(web, id: \.1) { item in
                        NavigationLink { WebSection(page: item.1, title: item.0) } label: { Label(item.0, systemImage: item.2) }
                    }
                }
                Section("Чертежи на устройстве") {
                    LabeledContent("Занято", value: Fmt.num(cacheMB, 1) + " МБ")
                    Button("Удалить скачанные чертежи", role: .destructive) { FileCache.clear(); cacheMB = 0 }
                }
                Section { Button("Выйти", role: .destructive) { askLogout = true } }
            }
            .navigationTitle("Ещё")
            .confirmationDialog("Выйти из ПТО-центра на этом устройстве?", isPresented: $askLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { store.logout() }
            }
            .onAppear { cacheMB = FileCache.sizeMB }
        }
    }
}

/// Разделы, которые пока остались в веб-версии: открываются внутри приложения с тем же входом
struct WebSection: View {
    @EnvironmentObject var store: Store
    let page: String, title: String
    var body: some View {
        WebPage(url: URL(string: API.base + "center/#" + page)!, token: store.token ?? "")
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct WebPage: UIViewRepresentable {
    let url: URL, token: String
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let safe = token.filter { $0.isHexDigit }
        let js = "try{localStorage.setItem('pto-center-token','\(safe)')}catch(e){};document.documentElement.classList.add('in-app')"
        cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.allowsBackForwardNavigationGestures = true
        v.load(URLRequest(url: url))
        return v
    }
    func updateUIView(_ v: WKWebView, context: Context) {}
}
