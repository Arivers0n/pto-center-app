import SwiftUI

@main
struct PTOApp: App {
    @StateObject private var store = Store()
    @StateObject private var theme = ThemeStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ShRoot()
                .environmentObject(store)
                .environmentObject(theme)
                .onChange(of: phase) { p in
                    if p == .active && store.loggedIn { store.start() } else if p == .background { store.stop() }
                }
                .onAppear { if store.loggedIn { store.start() } }
        }
    }
}

/// Корень: вход или оболочка; тема и акцент применяются ко всему окну
struct ShRoot: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if store.loggedIn { RootTabs() } else { LoginView() }
        }
        .tint(theme.tint(scheme))
        .preferredColorScheme(theme.preferredScheme)
    }
}

// MARK: - Разделы (те же группы, что в меню веб-версии)

enum ShGroup: String, CaseIterable, Identifiable {
    case work = "Работа", reference = "Справочники", personal = "Личное", app = "Программа"
    var id: String { rawValue }
}

enum ShSection: String, CaseIterable, Identifiable, Hashable {
    case home, calc, req, reqdash, schemes, journal, issues, joints, mats, pipes, sheets, contacts
    case work, norms, cheat
    case tasks, notes, expenses, timer, tabel
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Главная"
        case .calc: return "Калькуляторы"
        case .req: return "Заявки на ТМЦ"
        case .reqdash: return "Сводка заявок"
        case .schemes: return "Исполнительные схемы"
        case .journal: return "Журнал прораба"
        case .issues: return "Замечания"
        case .joints: return "Стыки"
        case .mats: return "Материалы"
        case .pipes: return "Сортамент труб"
        case .sheets: return "Расчётные листы"
        case .contacts: return "Контакты"
        case .work: return "Моя работа"
        case .norms: return "Нормативка"
        case .cheat: return "Шпаргалки ПТО"
        case .tasks: return "Мои задачи"
        case .notes: return "Заметки"
        case .expenses: return "Расходы"
        case .timer: return "Таймер"
        case .tabel: return "Табель"
        case .settings: return "Настройки"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .calc: return "function"
        case .req: return "shippingbox"
        case .reqdash: return "chart.bar"
        case .schemes: return "square.stack.3d.up"
        case .journal: return "list.bullet.clipboard"
        case .issues: return "exclamationmark.triangle"
        case .joints: return "flame"
        case .mats: return "cube.box"
        case .pipes: return "circle.circle"
        case .sheets: return "tablecells"
        case .contacts: return "person.2"
        case .work: return "briefcase"
        case .norms: return "books.vertical"
        case .cheat: return "lightbulb"
        case .tasks: return "checklist"
        case .notes: return "note.text"
        case .expenses: return "rublesign.circle"
        case .timer: return "timer"
        case .tabel: return "calendar"
        case .settings: return "gearshape"
        }
    }

    var group: ShGroup {
        switch self {
        case .home, .calc, .req, .reqdash, .schemes, .journal, .issues, .joints, .mats, .pipes, .sheets, .contacts: return .work
        case .work, .norms, .cheat: return .reference
        case .tasks, .notes, .expenses, .timer, .tabel: return .personal
        case .settings: return .app
        }
    }

    /// Пункты, которые можно скрыть в настройках («Меню»)
    static var hideable: [ShSection] { allCases.filter { $0 != .home && $0 != .settings } }
}

/// Экран раздела по имени из контракта: корневые экраны без собственного NavigationStack
struct ShScreenFactory: View {
    let section: ShSection
    let open: (ShSection) -> Void

    var body: some View {
        switch section {
        case .home: HomeView(go: open)
        case .calc: CalcView()
        case .req: RequestsView()
        case .reqdash: RequestsDashView()
        case .schemes: SchemesView()
        case .journal: JournalView()
        case .issues: IssuesView()
        case .joints: JointsView()
        case .mats: MaterialsView()
        case .pipes: PipesView()
        case .sheets: SheetsView()
        case .contacts: ContactsView()
        case .work: WorkView()
        case .norms: NormsView()
        case .cheat: CheatView()
        case .tasks: TasksView()
        case .notes: NotesView()
        case .expenses: ExpensesView()
        case .timer: TimerView()
        case .tabel: TabelView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Оболочка: iPad — боковое меню, iPhone — вкладки

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, requests, schemes, journal, more
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Главная"
        case .requests: return "Заявки"
        case .schemes: return "Схемы"
        case .journal: return "Журнал"
        case .more: return "Ещё"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .requests: return "shippingbox"
        case .schemes: return "square.stack.3d.up"
        case .journal: return "list.bullet.clipboard"
        case .more: return "ellipsis.circle"
        }
    }
    var section: ShSection? {
        switch self {
        case .home: return .home
        case .requests: return .req
        case .schemes: return .schemes
        case .journal: return .journal
        case .more: return nil
        }
    }
}

struct RootTabs: View {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.colorScheme) private var colorScheme
    @State private var current: ShSection = .home
    @State private var tab: AppTab = .home
    @State private var morePath: [ShSection] = []

    var body: some View {
        if size == .regular { sidebarLayout } else { tabLayout }
    }

    /// Переход к разделу из любого места (главная, плитки)
    private func open(_ s: ShSection) {
        if size == .regular { current = s; return }
        if let t = AppTab.allCases.first(where: { $0.section == s }) { tab = t; return }
        tab = .more
        morePath = [s]
    }

    // iPad
    private var sidebarLayout: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BrandHeader()
                        ForEach(ShGroup.allCases) { group in
                            let items = ShSection.allCases.filter { $0.group == group && theme.isVisible($0, keep: current) }
                            if !items.isEmpty { sidebarGroup(group, items: items) }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
                Divider()
                ProfileCard { current = .settings }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(theme.panel())
            }
            .navigationTitle("ПТО-центр")
            .navigationBarTitleDisplayMode(.inline)
            .ptoScreen()
        } detail: {
            NavigationStack { ShScreenFactory(section: current, open: open) }
                .id(current)
        }
    }

    private func sidebarGroup(_ group: ShGroup, items: [ShSection]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.rawValue).font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 10)
            VStack(spacing: 2) {
                ForEach(items) { section in
                    let selected = section == current
                    Button { current = section } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon).frame(width: 22)
                                .foregroundStyle(selected ? theme.tint(colorScheme) : Color.secondary)
                                .accessibilityHidden(true)
                            Text(section.title).font(.subheadline.weight(selected ? .semibold : .regular))
                            Spacer(minLength: 4)
                            if selected {
                                Image(systemName: "checkmark").font(.caption.weight(.semibold))
                                    .foregroundStyle(theme.tint(colorScheme)).accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(minHeight: 44)
                        .foregroundStyle(.primary)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8).fill(theme.tint(colorScheme).opacity(0.17))
                                RoundedRectangle(cornerRadius: 8).strokeBorder(theme.tint(colorScheme).opacity(0.55))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(4)
            .shPanel(12)
        }
    }

    // iPhone
    private var tabLayout: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { t in
                tabRoot(t).tabItem { Label(t.title, systemImage: t.icon) }.tag(t)
            }
        }
    }

    @ViewBuilder private func tabRoot(_ t: AppTab) -> some View {
        if let s = t.section {
            NavigationStack { ShScreenFactory(section: s, open: open) }
        } else {
            MoreView(path: $morePath, open: open)
        }
    }
}

/// Название объекта под названием программы (из «Настроек»)
private struct BrandHeader: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let sub = store.cfg["brandSub"].str
        if !sub.isEmpty {
            Text(sub).font(.footnote).foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        }
    }
}

// MARK: - Ещё (iPhone)

struct MoreView: View {
    @EnvironmentObject var theme: ThemeStore
    @Binding var path: [ShSection]
    let open: (ShSection) -> Void
    @State private var query = ""

    private static let inTabs: Set<ShSection> = [.home, .req, .schemes, .journal, .settings]
    private var groups: [ShGroup] { [.work, .reference, .personal] }

    private func items(_ g: ShGroup) -> [ShSection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ShSection.allCases.filter { s in
            guard s.group == g, !Self.inTabs.contains(s) else { return false }
            if q.isEmpty { return theme.isVisible(s) }
            return s.title.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if query.isEmpty {
                    Section {
                        ProfileCard { path = [.settings] }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                }
                ForEach(groups) { g in
                    let list = items(g)
                    if !list.isEmpty {
                        Section(g.rawValue) {
                            ForEach(list) { s in
                                NavigationLink(value: s) { Label(s.title, systemImage: s.icon) }
                            }
                        }
                    }
                }
                if query.isEmpty {
                    Section { SyncPill() }
                }
            }
            .navigationTitle("Ещё")
            .searchable(text: $query, prompt: "Найти раздел")
            .navigationDestination(for: ShSection.self) { s in
                ShScreenFactory(section: s, open: open)
            }
            .ptoScreen()
        }
    }
}

// MARK: - Профиль

struct ProfileCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme
    let action: () -> Void

    private var name: String { let n = store.kv("name").str; return n.isEmpty ? "Инженер ПТО" : n }
    private var post: String { let p = store.cfg["post"].str; return p.isEmpty ? "Инженер ПТО" : p }
    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        let tint = theme.tint(scheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Text(initials).font(.subheadline.bold()).foregroundStyle(theme.onTint(scheme)).frame(width: 36, height: 36)
                    .background(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                    Text(post).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10).frame(minHeight: 44)
            .shPanel(14)
        }
        .buttonStyle(Pressable())
        .accessibilityLabel("Профиль: \(name), \(post). Открыть настройки")
    }
}

// MARK: - Вход

struct LoginView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @State private var user = ""
    @State private var pass = ""
    @State private var busy = false
    @State private var err: String?
    @FocusState private var focus: Field?
    private enum Field { case user, pass }

    private var canSubmit: Bool { !busy && !user.isEmpty && !pass.isEmpty }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 28) {
                    header
                    form
                    if let err {
                        Text(err).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    submit
                    Text("Тот же логин, что в ПТО-центре в браузере").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 400)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .ptoScreen()
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image("Logo").resizable().frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: theme.tint(scheme).opacity(0.35), radius: 16, y: 8)
                .accessibilityHidden(true)
            Text("ПТО-центр").font(.largeTitle.bold())
            Text("Заявки, исполнительные схемы и журнал прораба")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person").foregroundStyle(.secondary).frame(width: 20)
                TextField("Логин", text: $user)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .user).submitLabel(.next)
                    .onSubmit { focus = .pass }
            }
            .padding(.horizontal, 14).frame(minHeight: 50)
            Divider().padding(.leading, 46)
            HStack(spacing: 12) {
                Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 20)
                SecureField("Пароль", text: $pass)
                    .textContentType(.password)
                    .focused($focus, equals: .pass).submitLabel(.go)
                    .onSubmit(go)
            }
            .padding(.horizontal, 14).frame(minHeight: 50)
        }
        .shPanel(14)
    }

    private var submit: some View {
        Button(action: go) {
            HStack(spacing: 8) {
                if busy { ProgressView() }
                Text("Войти").bold()
            }
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(!canSubmit)
    }

    private func go() {
        guard canSubmit else { return }
        busy = true; err = nil; focus = nil
        Task {
            do { try await store.login(user, pass); store.start() } catch { err = error.localizedDescription }
            busy = false
        }
    }
}
