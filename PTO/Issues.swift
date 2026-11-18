import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Общее для группы «Списки и личное» (префикс Ls)

enum LsKind { case text, multiline, number, date, pick([String]), phone, email }

struct LsFieldSpec: Identifiable {
    let key: String
    let title: String
    var kind: LsKind = .text
    var id: String { key }
}

/// Какой лист открыт: пустая запись значит «новая»
struct LsSheet: Identifiable {
    let id = UUID()
    let rec: Rec?
}

@MainActor
enum LsHaptic {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

/// CSV для Excel: UTF-8 с BOM, разделитель «;»
struct LsCSV: Transferable {
    let name: String
    let rows: [[String]]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { (csv: LsCSV) in
            SentTransferredFile(try csv.write())
        }
    }

    func write() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let lines: [String] = rows.map { row in row.map { LsCSV.cell($0) }.joined(separator: ";") }
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(lines.joined(separator: "\r\n").utf8))
        try data.write(to: url, options: .atomic)
        return url
    }

    static func cell(_ s: String) -> String {
        let risky = s.contains(";") || s.contains("\"") || s.contains("\n") || s.contains("\r")
        return risky ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
}

struct LsShareButton: View {
    let csv: LsCSV
    var body: some View {
        ShareLink(item: csv, preview: SharePreview(csv.name)) {
            Label("В Excel", systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel("Выгрузить в Excel")
    }
}

/// Число для CSV: запятая как десятичный знак, без пробелов
func lsPlain(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(v).replacingOccurrences(of: ".", with: ",")
}

/// Склонение: «1 раз», «2 раза», «5 раз»
func lsPlural(_ n: Int, _ a: String, _ b: String, _ c: String) -> String {
    let m = abs(n) % 100, k = m % 10
    let word = (m > 10 && m < 20) ? c : (k == 1 ? a : ((k > 1 && k < 5) ? b : c))
    return "\(n) \(word)"
}

extension View {
    /// На iPad списки и формы не растягиваются на весь экран
    func lsColumn() -> some View {
        self.frame(maxWidth: 720).frame(maxWidth: .infinity)
    }

    func lsSwipeDelete(_ action: @escaping () -> Void) -> some View {
        self.swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { action() } label: { Label("Удалить", systemImage: "trash") }
        }
    }
}

struct LsStat: View {
    let value: String
    let label: String
    var tint: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit().foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Горизонтальная полоса фильтров
struct LsChips: View {
    let items: [(title: String, count: Int?)]
    @Binding var selected: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.title) { item in
                    Chip(title: item.title, count: item.count, on: selected == item.title) { selected = item.title }
                }
            }
            .padding(.horizontal, 16)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

// MARK: - Форма записи: поля по описанию, чужие поля записи сохраняются

struct LsRecordForm: View {
    let title: String
    let specs: [LsFieldSpec]
    let rec: Rec?
    let required: (key: String, message: String)?
    let validate: (([String: String]) -> String?)?
    let hint: (([String: String]) -> String?)?
    let newExtras: [String: JSON]
    let onSave: (Rec) -> Void
    let onDelete: ((Rec) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: String?
    @State private var draft: [String: String]
    @State private var error: String?
    @State private var confirmDelete = false

    init(title: String, specs: [LsFieldSpec], rec: Rec?, defaults: [String: String] = [:],
         required: (key: String, message: String)? = nil,
         validate: (([String: String]) -> String?)? = nil,
         hint: (([String: String]) -> String?)? = nil,
         newExtras: [String: JSON] = [:],
         onSave: @escaping (Rec) -> Void, onDelete: ((Rec) -> Void)? = nil) {
        self.title = title; self.specs = specs; self.rec = rec
        self.required = required; self.validate = validate; self.hint = hint
        self.newExtras = newExtras; self.onSave = onSave; self.onDelete = onDelete
        var d: [String: String] = [:]
        for s in specs {
            let cur = rec?[s.key].str ?? ""
            d[s.key] = cur.isEmpty ? (defaults[s.key] ?? "") : cur
        }
        _draft = State(initialValue: d)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(specs) { s in fieldRow(s) }
                } footer: {
                    footer
                }
                if rec != nil, onDelete != nil {
                    Section {
                        Button("Удалить запись", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { commit() }.bold() }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { focus = nil }
                }
            }
            .confirmationDialog("Удалить запись?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let rec { onDelete?(rec) }
                    dismiss()
                }
            }
            .ptoScreen()
        }
    }

    @ViewBuilder private var footer: some View {
        if let error {
            Text(error).foregroundStyle(.red)
        } else if let h = hint?(draft) {
            Text(h)
        }
    }

    private func bind(_ key: String) -> Binding<String> {
        Binding<String>(get: { draft[key] ?? "" }, set: { draft[key] = $0; error = nil })
    }

    @ViewBuilder private func fieldRow(_ s: LsFieldSpec) -> some View {
        switch s.kind {
        case .date:
            dateRow(s)
        case .pick(let options):
            pickRow(s, options)
        case .multiline:
            labeled(s.title) {
                TextField("", text: bind(s.key), axis: .vertical)
                    .lineLimit(2...6).focused($focus, equals: s.key)
            }
        case .number:
            labeled(s.title) {
                TextField("", text: bind(s.key)).keyboardType(.decimalPad).focused($focus, equals: s.key)
            }
        case .phone:
            labeled(s.title) {
                TextField("", text: bind(s.key)).keyboardType(.phonePad).focused($focus, equals: s.key)
            }
        case .email:
            labeled(s.title) {
                TextField("name@company.ru", text: bind(s.key))
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().focused($focus, equals: s.key)
            }
        case .text:
            labeled(s.title) {
                TextField("", text: bind(s.key)).focused($focus, equals: s.key)
            }
        }
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func pickRow(_ s: LsFieldSpec, _ options: [String]) -> some View {
        let cur = draft[s.key] ?? ""
        let all = (cur.isEmpty || options.contains(cur)) ? options : options + [cur]
        return Picker(s.title, selection: bind(s.key)) {
            ForEach(all, id: \.self) { Text($0).tag($0) }
        }
    }

    private func dateRow(_ s: LsFieldSpec) -> some View {
        let text = draft[s.key] ?? ""
        let dateBinding = Binding<Date>(
            get: { Fmt.date(draft[s.key] ?? "") ?? Date() },
            set: { draft[s.key] = Fmt.iso.string(from: $0) })
        return HStack {
            Text(s.title)
            Spacer()
            if Fmt.date(text) != nil {
                DatePicker(s.title, selection: dateBinding, displayedComponents: .date)
                    .labelsHidden().environment(\.locale, Locale(identifier: "ru_RU"))
                Button { draft[s.key] = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless).accessibilityLabel("Убрать дату")
            } else {
                Button("Указать") { draft[s.key] = Fmt.today }.buttonStyle(.borderless)
            }
        }
        .frame(minHeight: 44)
    }

    private func isBlank(_ key: String) -> Bool {
        let text = (draft[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = specs.first(where: { $0.key == key }), case .number = s.kind {
            return (JSON.s(text).num ?? 0) <= 0
        }
        return text.isEmpty
    }

    private func value(_ s: LsFieldSpec) -> JSON {
        let text = draft[s.key] ?? ""
        switch s.kind {
        case .number: return .n(JSON.s(text).num ?? 0)
        case .multiline: return .s(text)
        default: return .s(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func commit() {
        if let r = required, isBlank(r.key) { fail(r.message); return }
        if let e = validate?(draft) { fail(e); return }
        var out = rec ?? Rec(id: Fmt.uid(), v: .o(newExtras))
        for s in specs { out.v[s.key] = value(s) }
        onSave(out)
        LsHaptic.success()
        dismiss()
    }

    private func fail(_ message: String) {
        error = message
        LsHaptic.warning()
    }
}

// MARK: - Замечания и поручения

struct IssuesView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var filter = "Все"
    @State private var sheet: LsSheet?

    private static let statuses = ["Открыто", "В работе", "Устранено", "Закрыто"]
    private static let specs: [LsFieldSpec] = [
        LsFieldSpec(key: "src", title: "Источник", kind: .pick(["Заказчик", "Генподрядчик", "Проектировщик", "Эксплуатация", "Госорган", "Внутреннее"])),
        LsFieldSpec(key: "text", title: "Содержание", kind: .multiline),
        LsFieldSpec(key: "owner", title: "Ответственный"),
        LsFieldSpec(key: "due", title: "Срок", kind: .date),
        LsFieldSpec(key: "status", title: "Статус", kind: .pick(statuses))
    ]

    private func isDone(_ r: Rec) -> Bool { r["status"].str == "Закрыто" || r["status"].str == "Устранено" }
    private func isLate(_ r: Rec) -> Bool { !isDone(r) && !r["due"].str.isEmpty && r["due"].str < Fmt.today }
    private func color(_ r: Rec) -> Color { isDone(r) ? .green : (isLate(r) ? .red : .orange) }

    private var all: [Rec] { store.list("issues") }

    private var rows: [Rec] {
        let q = query.lowercased()
        let found = all.filter { r in
            let byStatus = filter == "Все" || r["status"].str == filter
            let hay = [r["text"].str, r["owner"].str, r["src"].str].joined(separator: " ").lowercased()
            return byStatus && (q.isEmpty || hay.contains(q))
        }
        return found.sorted { a, b in
            if isDone(a) != isDone(b) { return !isDone(a) }
            if a["due"].str != b["due"].str { return a["due"].str < b["due"].str }
            return a.id < b.id
        }
    }

    private var chips: [(title: String, count: Int?)] {
        var out: [(title: String, count: Int?)] = [("Все", all.count)]
        for s in Self.statuses { out.append((s, all.filter { $0["status"].str == s }.count)) }
        return out
    }

    var body: some View {
        List {
            if !all.isEmpty {
                LsChips(items: chips, selected: $filter)
                Section {
                    HStack {
                        LsStat(value: "\(all.count)", label: "всего")
                        LsStat(value: "\(all.filter { isLate($0) }.count)", label: "просрочено", tint: .red)
                        LsStat(value: "\(all.filter { !isDone($0) }.count)", label: "не закрыто")
                    }
                }
            }
            Section {
                if rows.isEmpty {
                    EmptyNote(title: all.isEmpty ? "Замечаний пока нет" : "Ничего не найдено",
                              text: all.isEmpty ? "Запишите первое кнопкой «+»." : "Измените поиск или фильтр.")
                }
                ForEach(rows) { r in row(r) }
            } footer: {
                Text("Просроченные подсвечиваются красным")
            }
        }
        .navigationTitle("Замечания и поручения")
        .searchable(text: $query, prompt: "Поиск по замечаниям")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { sheet = LsSheet(rec: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Добавить замечание")
            }
        }
        .sheet(item: $sheet) { s in form(s) }
        .lsColumn()
        .ptoScreen()
    }

    private func row(_ r: Rec) -> some View {
        Button { sheet = LsSheet(rec: r) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(r["text"].str).foregroundStyle(.primary).multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text(subtitle(r)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if !r["due"].str.isEmpty { Badge(text: Fmt.show(r["due"].str), color: color(r)) }
                    Badge(text: r["status"].str, color: isDone(r) ? .green : .secondary)
                }
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .swipeActions(edge: .leading) {
            if !isDone(r) {
                Button { setStatus(r, "Закрыто") } label: { Label("Закрыто", systemImage: "checkmark") }.tint(.green)
            }
        }
        .lsSwipeDelete { withAnimation { store.delete("issues", r.id) } }
    }

    private func subtitle(_ r: Rec) -> String {
        [r["src"].str, r["owner"].str, Fmt.show(r["date"].str)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func setStatus(_ r: Rec, _ status: String) {
        var n = r
        n.v["status"] = .s(status)
        withAnimation { store.put("issues", n) }
        LsHaptic.success()
    }

    private func form(_ s: LsSheet) -> some View {
        LsRecordForm(title: s.rec == nil ? "Новое замечание" : "Замечание", specs: Self.specs, rec: s.rec,
                     defaults: ["src": "Заказчик", "due": Fmt.today, "status": "Открыто"],
                     required: (key: "text", message: "Опишите замечание: что не так и где"),
                     newExtras: ["date": .s(Fmt.today)],
                     onSave: { r in withAnimation { store.put("issues", r) } },
                     onDelete: { r in store.delete("issues", r.id) })
    }
}
