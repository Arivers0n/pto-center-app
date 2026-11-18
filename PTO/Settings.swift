import SwiftUI
import UniformTypeIdentifiers

// MARK: - Запись настроек

extension Store {
    /// Меняет один ключ в общих настройках (cfg), не трогая остальные
    func shSetCfg(_ key: String, _ value: JSON) {
        var c = cfg
        if case .o = c {} else { c = .o([:]) }
        c[key] = value
        setKV("cfg", c)
    }
}

private func shShort(_ project: String) -> String {
    project.replacingOccurrences(of: "\\s+цех$", with: "", options: [.regularExpression, .caseInsensitive])
        .trimmingCharacters(in: .whitespaces)
}

private func shUnique(_ list: [String]) -> [String] {
    var seen = Set<String>()
    return list.filter { seen.insert($0).inserted }
}

// MARK: - Поле текста: запись на сервер при выходе из поля, а не на каждую букву

private struct ShField: View {
    @EnvironmentObject var store: Store
    let title: String
    let key: String
    var isKV = false
    var multiline = false
    var placeholder = "—"
    @State private var text = ""
    @State private var loaded = ""
    @FocusState private var focused: Bool

    private var current: String { isKV ? store.kv(key).str : store.cfg[key].str }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if multiline {
                TextField(placeholder, text: $text, axis: .vertical).lineLimit(2...6)
                    .focused($focused)
            } else {
                TextField(placeholder, text: $text).focused($focused).onSubmit(commit)
            }
        }
        .onAppear { text = current; loaded = current }
        .onChange(of: focused) { f in if !f { commit() } }
        .onChange(of: current) { v in if !focused && text == loaded { text = v; loaded = v } }
        .onDisappear(perform: commit)
    }

    private func commit() {
        let value = multiline ? text : text.trimmingCharacters(in: .whitespaces)
        guard value != loaded else { return }
        loaded = value
        if isKV { store.setKV(key, .s(value)) } else { store.shSetCfg(key, .s(value)) }
    }
}

// MARK: - Окно имени (для списков)

private struct ShNameTarget: Identifiable {
    let id = UUID()
    let old: String?
}

private struct ShNameSheet: View {
    let title: String
    let initial: String
    let save: (String) -> String?   // текст ошибки или nil
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $text).focused($focused).onSubmit(done)
                } footer: {
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: done).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { text = initial; focused = true }
        }
        .presentationDetents([.height(240)])
    }

    private func done() {
        let v = text.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        if let e = save(v) { error = e } else { dismiss() }
    }
}

/// Список строк с добавлением, переименованием и удалением
private struct ShListSection: View {
    let title: String
    let footer: String
    let addTitle: String
    let items: [String]
    let detail: (String) -> String?
    let canDelete: (String) -> Bool
    let save: (String?, String) -> String?
    let remove: (String) -> Void
    @State private var target: ShNameTarget?

    var body: some View {
        Section {
            ForEach(items, id: \.self) { item in
                Button { target = ShNameTarget(old: item) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item).foregroundStyle(.primary)
                            if let d = detail(item) { Text(d).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    if canDelete(item) {
                        Button(role: .destructive) { withAnimation { remove(item) } } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
            Button { target = ShNameTarget(old: nil) } label: { Label(addTitle, systemImage: "plus") }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
        .sheet(item: $target) { t in
            ShNameSheet(title: t.old == nil ? addTitle : "Переименовать", initial: t.old ?? "") { save(t.old, $0) }
        }
    }
}

// MARK: - Резервная копия: весь набор данных одним JSON

struct ShBackup: Transferable {
    let cols: [String: [String: JSON]]

    func data() throws -> Data {
        var out: [String: JSON] = [:]
        for (name, records) in cols {
            if name == "kv" {
                for (key, value) in records { out[key] = value }
            } else {
                let list: [JSON] = records.keys.sorted().map { id -> JSON in
                    var o = records[id]?.obj ?? [:]
                    o["id"] = .s(id)
                    return .o(o)
                }
                out[name] = .a(list)
            }
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try enc.encode(JSON.o(out))
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { backup in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ПТО-центр_копия_\(Fmt.today).json")
            try backup.data().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

// MARK: - Плитка темы

private struct ShSkinTile: View {
    let skin: ShSkin
    let selected: Bool
    let tap: () -> Void
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = skin.spec
        let accent = Color(shHex: s.accent)
        let ink = Color(shHex: s.text)
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    ShBackdrop(skin: skin, base: Color(shHex: s.bg))
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(shHex: s.panel)).frame(width: 26)
                        VStack(alignment: .leading, spacing: 5) {
                            Capsule().fill(accent).frame(width: 30, height: 7)
                            Capsule().fill(ink.opacity(0.55)).frame(height: 6)
                            Capsule().fill(ink.opacity(0.3)).frame(width: 44, height: 6)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1))
                Text(s.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.tint(scheme), lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(Pressable())
        .accessibilityLabel(s.title)
        .accessibilityHint(s.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Настройки

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @State private var askLogout = false
    @State private var cacheMB = FileCache.sizeMB
    @State private var secTarget: ReqSection?
    @State private var newSec = false

    var body: some View {
        Form {
            profileSection
            appearanceSection
            requisitesSection
            printSection
            projectsSection
            requestSectionsSection
            worksSection
            menuSection
            syncSection
            filesSection
            backupSection
            aboutSection
        }
        .navigationTitle("Настройки")
        .ptoScreen()
        .sheet(item: $secTarget) { s in ShSecSheet(section: s, isNew: false) }
        .sheet(isPresented: $newSec) { ShSecSheet(section: nil, isNew: true) }
        .confirmationDialog("Выйти из ПТО-центра на этом устройстве?", isPresented: $askLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { store.logout() }
        }
        .onAppear { cacheMB = FileCache.sizeMB }
    }

    // MARK: Профиль и реквизиты

    private var profileSection: some View {
        Section {
            ShField(title: "Ваше имя", key: "name", isKV: true, placeholder: "Например: Андрей Иванов")
            ShField(title: "Должность", key: "post", placeholder: "Инженер ПТО")
            ShField(title: "Объект (под названием программы)", key: "brandSub")
        } header: {
            Text("Профиль")
        } footer: {
            Text("Имя и должность видны в углу программы.")
        }
    }

    private var requisitesSection: some View {
        Group {
            Section("Организация") {
                ShField(title: "Организация (в заявках)", key: "company")
                ShField(title: "Договор", key: "contract")
            }
            Section("Подписанты заявок") {
                ShField(title: "Выдал: должность", key: "issuerPost")
                ShField(title: "Выдал: ФИО", key: "issuerName")
                ShField(title: "Получил: должность", key: "receiverPost")
                ShField(title: "Получил: ФИО", key: "receiverName")
            }
            Section {
                ShField(title: "Другие «Выдал»", key: "issuersText", multiline: true,
                        placeholder: "Руководитель проекта | А.Грибков")
                ShField(title: "Другие «Получил»", key: "receiversText", multiline: true,
                        placeholder: "Начальник участка | Красов А.С.")
            } footer: {
                Text("По строке: должность | ФИО. Если подписантов больше одного, при печати спросим, кто.")
            }
        }
    }

    private var printSection: some View {
        Section {
            Toggle("Спрашивать, когда есть что выбрать", isOn: boolBinding("askPrint"))
            Toggle("Сразу открывать окно печати", isOn: boolBinding("autoPrint"))
        } header: {
            Text("Печать заявок")
        } footer: {
            Text("Подписант, пустые строки, цех. Если выбирать нечего, печать идёт сразу.")
        }
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(get: {
            if case .b(let v)? = store.cfg[key] { return v }
            return true
        }, set: { store.shSetCfg(key, .b($0)) })
    }

    // MARK: Оформление

    private var appearanceSection: some View {
        Group {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(ShSkin.allCases) { skin in
                        ShSkinTile(skin: skin, selected: theme.skin == skin) {
                            withAnimation(.easeInOut(duration: 0.25)) { theme.skin = skin }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .listRowBackground(Color.clear)
                if theme.skin == .standard {
                    Picker("Вид", selection: $theme.appearance) {
                        ForEach(ShAppearance.allCases) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text("Тема оформления")
            } footer: {
                Text("Тема, акцент и плотность у каждого устройства свои и на сервер не отправляются. \(theme.skin.spec.detail).")
            }
            Section("Цвет и плотность") {
                accentRow
                Picker("Плотность", selection: $theme.compact) {
                    Text("Обычно").tag(false)
                    Text("Плотно").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Меньше прозрачности", isOn: $theme.solid)
            }
        }
    }

    private var accentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Акцентный цвет").font(.subheadline)
            HStack(spacing: 14) {
                ForEach(ShAccent.allCases) { a in
                    let dark = theme.effective(scheme) == .dark
                    let c = a == .skin ? Color(shHex: theme.skin.spec.accent) : Color(shHex: dark ? a.hex.dark : a.hex.light)
                    Button { theme.accent = a } label: {
                        Circle().fill(c).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: theme.accent == a ? 2.5 : 0).padding(-4))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Акцент: \(a.title)")
                    .accessibilityAddTraits(theme.accent == a ? .isSelected : [])
                }
            }
            Text("Кнопки, выделение, активные вкладки").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Проекты, разделы, виды работ

    private var projectsSection: some View {
        ShListSection(title: "Проекты",
                      footer: "Цеха, корпуса и объекты. По ним делятся закрытия КС, схемы и заявки. Переименование сразу меняет название во всех записях.",
                      addTitle: "Добавить проект",
                      items: shUnique(store.shops),
                      detail: { projectUse($0).summary },
                      canDelete: { projectUse($0).total == 0 },
                      save: saveProject,
                      remove: { name in store.shSetCfg("shops", .a(store.shops.filter { $0 != name }.map { JSON.s($0) })) })
    }

    private struct ProjectUse {
        let requests: Int, closings: Int, schemes: Int
        var total: Int { requests + closings + schemes }
        var summary: String { "\(closings) закр. · \(schemes) схем · \(requests) заявок" }
    }

    private func projectUse(_ full: String) -> ProjectUse {
        let short = shShort(full)
        return ProjectUse(requests: store.list("requests").filter { $0["shop"].str == full }.count,
                          closings: store.list("closings").filter { $0["shop"].str == short }.count,
                          schemes: store.list("schemes").filter { $0["shop"].str == short }.count)
    }

    private func saveProject(_ old: String?, _ new: String) -> String? {
        var list = store.shops
        let clash = list.contains { shShort($0).lowercased() == shShort(new).lowercased() && $0 != old }
        if clash { return "Такой проект уже есть" }
        guard let old else {
            list.append(new)
            store.shSetCfg("shops", .a(list.map { JSON.s($0) }))
            return nil
        }
        if old == new { return nil }
        guard let i = list.firstIndex(of: old) else { return nil }
        list[i] = new
        store.shSetCfg("shops", .a(list.map { JSON.s($0) }))
        renameProject(from: old, to: new)
        return nil
    }

    /// Как projRename в вебе: заявки хранят полное название, закрытия и схемы — короткое
    private func renameProject(from old: String, to new: String) {
        let oldShort = shShort(old), newShort = shShort(new)
        for r in store.list("requests") where r["shop"].str == old {
            var c = r; c.v["shop"] = .s(new); store.put("requests", c)
        }
        for col in ["closings", "schemes"] {
            for r in store.list(col) where r["shop"].str == oldShort {
                var c = r; c.v["shop"] = .s(newShort); store.put(col, c)
            }
        }
    }

    private var requestSectionsSection: some View {
        Section {
            ForEach(store.reqSections) { s in
                Button { secTarget = s } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).foregroundStyle(.primary)
                            Text("\(sectionCount(s)) заявок" + (s.full != s.name ? " · \(s.full)" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    if sectionCount(s) == 0 && store.reqSections.count > 1 {
                        Button(role: .destructive) { withAnimation { removeSection(s) } } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
            Button { newSec = true } label: { Label("Добавить раздел", systemImage: "plus") }
        } header: {
            Text("Разделы заявок")
        } footer: {
            Text("Вкладки в «Заявках на ТМЦ», у каждого раздела своя нумерация. Удалить можно раздел без заявок.")
        }
    }

    private func sectionCount(_ s: ReqSection) -> Int {
        store.list("requests").filter { $0["sec"].str == s.id }.count
    }

    private func removeSection(_ s: ReqSection) {
        writeSections(store.reqSections.filter { $0.id != s.id })
    }

    private func writeSections(_ list: [ReqSection]) {
        let json: [JSON] = list.map { .o(["id": .s($0.id), "name": .s($0.name), "full": .s($0.full)]) }
        store.shSetCfg("reqSecs", .a(json))
    }

    private var worksSection: some View {
        let works = shUnique(store.cfg["works"].arr.map(\.str).filter { !$0.isEmpty })
        return ShListSection(title: "Виды работ",
                             footer: "Подсказки в заявках на ТМЦ.",
                             addTitle: "Добавить вид работ",
                             items: works,
                             detail: { _ in nil },
                             canDelete: { _ in true },
                             save: { old, new in
                                 if works.contains(new) && old != new { return "Такой вид работ уже есть" }
                                 var list = works
                                 if let old, let i = list.firstIndex(of: old) { list[i] = new } else { list.append(new) }
                                 store.shSetCfg("works", .a(list.map { JSON.s($0) }))
                                 return nil
                             },
                             remove: { name in store.shSetCfg("works", .a(works.filter { $0 != name }.map { JSON.s($0) })) })
    }

    // MARK: Меню

    private var menuSection: some View {
        Section {
            ForEach(ShSection.hideable) { s in
                Toggle(isOn: Binding(get: { theme.isVisible(s) }, set: { theme.setHidden(s, !$0) })) {
                    Label(s.title, systemImage: s.icon)
                }
            }
        } header: {
            Text("Меню")
        } footer: {
            Text("Снимите переключатель, чтобы убрать пункт из бокового меню и списка «Ещё». Раздел остаётся доступен через поиск в «Ещё».")
        }
    }

    // MARK: Синхронизация, файлы, копия

    private var syncSection: some View {
        Section {
            SyncPill()
            LabeledContent("Сервер", value: URL(string: API.base)?.host ?? "не задан")
            if let d = store.lastSync { LabeledContent("Последняя синхронизация", value: d.formatted(date: .omitted, time: .shortened)) }
            if store.pendingCount > 0 { LabeledContent("Ждёт отправки", value: "\(store.pendingCount)") }
            Button("Синхронизировать сейчас") { Task { await store.sync() } }
        } header: {
            Text("Сервер")
        } footer: {
            Text("Данные хранятся на сервере и одинаковы на всех устройствах, где вы вошли.")
        }
    }

    private var filesSection: some View {
        Section {
            LabeledContent("Занято", value: Fmt.num(cacheMB, 1) + " МБ")
            Button("Удалить скачанные чертежи", role: .destructive) { FileCache.clear(); cacheMB = 0 }
        } header: {
            Text("Чертежи на устройстве")
        } footer: {
            Text("Чертёж скачивается при первом открытии, затем открывается сразу. После очистки скачается заново.")
        }
    }

    private var backupSection: some View {
        Section {
            ShareLink(item: ShBackup(cols: store.cols), preview: SharePreview("Резервная копия ПТО-центра")) {
                Label("Сохранить резервную копию", systemImage: "square.and.arrow.up")
            }
            NavigationLink { ActualizeView() } label: {
                Label("Актуализация данных", systemImage: "wand.and.stars")
            }
        } header: {
            Text("Данные")
        } footer: {
            Text("Копия — один файл .json со всеми заявками, схемами, журналом и настройками. Актуализация находит пустые заявки, повторы и записи без раздела.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Версия", value: appVersion)
            Button("Выйти", role: .destructive) { askLogout = true }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}

// MARK: - Раздел заявок: имя на вкладке и полное

private struct ShSecSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let section: ReqSection?
    let isNew: Bool
    @State private var name = ""
    @State private var full = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("На вкладке", text: $name)
                    TextField("Полное название", text: $full)
                } footer: {
                    Text("Короткое название — на вкладке, полное — в шапке заявки. У раздела своя нумерация.")
                }
            }
            .navigationTitle(isNew ? "Новый раздел" : "Раздел заявок").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { name = section?.name ?? ""; full = (section?.full == section?.name ? "" : section?.full) ?? "" }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let f = full.trimmingCharacters(in: .whitespaces)
        var list = store.reqSections
        if let s = section, let i = list.firstIndex(where: { $0.id == s.id }) {
            list[i] = ReqSection(id: s.id, name: n, full: f.isEmpty ? n : f)
        } else {
            let next = (list.compactMap { Int($0.id) }.max() ?? 0) + 1
            list.append(ReqSection(id: String(next), name: n, full: f.isEmpty ? n : f))
        }
        let json: [JSON] = list.map { .o(["id": .s($0.id), "name": .s($0.name), "full": .s($0.full)]) }
        store.shSetCfg("reqSecs", .a(json))
        dismiss()
    }
}
