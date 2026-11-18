import SwiftUI

// MARK: - Мои задачи

struct TasksView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var sheet: LsSheet?

    private static let specs: [LsFieldSpec] = [
        LsFieldSpec(key: "text", title: "Новая задача", kind: .multiline),
        LsFieldSpec(key: "due", title: "Срок", kind: .date),
        LsFieldSpec(key: "prio", title: "Важность", kind: .pick(["Высокий", "Средний", "Низкий"]))
    ]

    private func isDone(_ t: Rec) -> Bool { t["done"]?.bool ?? false }

    private var rows: [Rec] {
        let q = query.lowercased()
        let found = store.list("tasks").filter { q.isEmpty || $0["text"].str.lowercased().contains(q) }
        return found.sorted { a, b in
            if isDone(a) != isDone(b) { return !isDone(a) }
            if a["due"].str != b["due"].str { return a["due"].str < b["due"].str }
            return a.id < b.id
        }
    }

    var body: some View {
        List {
            if rows.isEmpty {
                EmptyNote(title: store.list("tasks").isEmpty ? "Задач нет — отдыхайте" : "Ничего не найдено",
                          text: store.list("tasks").isEmpty ? "Нажмите «+», чтобы добавить дело." : "Измените поиск.")
            }
            ForEach(rows) { t in row(t) }
        }
        .navigationTitle("Мои задачи")
        .searchable(text: $query, prompt: "Поиск по задачам")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { sheet = LsSheet(rec: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Добавить задачу")
            }
        }
        .sheet(item: $sheet) { s in form(s) }
        .animation(.default, value: rows)
        .lsColumn()
        .ptoScreen()
    }

    private func row(_ t: Rec) -> some View {
        let done = isDone(t)
        let due = t["due"].str
        let late = !done && !due.isEmpty && due < Fmt.today
        let prio = t["prio"].str
        let prioColor: Color = prio == "Высокий" ? .red : (prio == "Средний" ? .orange : .secondary)
        return HStack(spacing: 12) {
            Button { toggle(t) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(done ? Color.green : Color.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(done ? "Вернуть в работу" : "Отметить выполненной")
            Button { sheet = LsSheet(rec: t) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t["text"].str).strikethrough(done).foregroundStyle(done ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if !prio.isEmpty { Badge(text: prio, color: prioColor) }
                        if !due.isEmpty { Badge(text: Fmt.show(due), color: late ? .red : .secondary) }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .lsSwipeDelete { withAnimation { store.delete("tasks", t.id) } }
    }

    private func toggle(_ t: Rec) {
        var n = t
        n.v["done"] = .b(!isDone(t))
        withAnimation { store.put("tasks", n) }
        LsHaptic.tap()
    }

    private func form(_ s: LsSheet) -> some View {
        LsRecordForm(title: s.rec == nil ? "Новая задача" : "Задача", specs: Self.specs, rec: s.rec,
                     defaults: ["due": Fmt.today, "prio": "Средний"],
                     required: (key: "text", message: "Напишите, что нужно сделать"),
                     newExtras: ["done": .b(false)],
                     onSave: { r in withAnimation { store.put("tasks", r) } },
                     onDelete: { r in store.delete("tasks", r.id) })
    }
}

// MARK: - Заметки

private let lsNoteColors: [(key: String, color: Color, name: String)] = [
    ("c1", Color.pto, "Синий"), ("c2", .green, "Зелёный"), ("c3", .orange, "Жёлтый"), ("c4", .red, "Красный")
]

private func lsNoteColor(_ key: String) -> Color {
    lsNoteColors.first { $0.key == key }?.color ?? Color.pto
}

struct NotesView: View {
    @EnvironmentObject var store: Store
    @State private var query = ""
    @State private var sheet: LsSheet?

    private var all: [Rec] { store.list("notes") }

    private var rows: [Rec] {
        let q = query.lowercased()
        let found = all.filter { q.isEmpty || ($0["title"].str + " " + $0["text"].str).lowercased().contains(q) }
        return found.sorted { $0.id > $1.id }
    }

    var body: some View {
        ScrollView {
            if rows.isEmpty {
                EmptyNote(title: all.isEmpty ? "Заметок нет" : "Ничего не найдено",
                          text: all.isEmpty ? "Телефоны, списки, идеи: нажмите «+»." : "Измените поиск.")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(rows) { n in card(n) }
            }
            .padding(16)
        }
        .navigationTitle("Заметки")
        .searchable(text: $query, prompt: "Поиск по заметкам")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { sheet = LsSheet(rec: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Новая заметка")
            }
        }
        .sheet(item: $sheet) { s in LsNoteEditor(rec: s.rec, count: all.count) }
        .animation(.default, value: rows)
        .lsColumn()
        .ptoScreen()
    }

    private func card(_ n: Rec) -> some View {
        Button { sheet = LsSheet(rec: n) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(n["title"].str).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text(n["text"].str).font(.subheadline).foregroundStyle(.secondary).lineLimit(6)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .top) {
                Rectangle().fill(lsNoteColor(n["c"].str)).frame(height: 4).clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.horizontal, 14)
            }
        }
        .buttonStyle(Pressable())
        .contextMenu {
            Button(role: .destructive) { withAnimation { store.delete("notes", n.id) } } label: { Label("Удалить", systemImage: "trash") }
        }
    }
}

private struct LsNoteEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let rec: Rec?
    let count: Int
    @State private var title: String
    @State private var text: String
    @State private var color: String
    @State private var confirmDelete = false

    init(rec: Rec?, count: Int) {
        self.rec = rec; self.count = count
        _title = State(initialValue: rec?["title"].str ?? "Новая заметка")
        _text = State(initialValue: rec?["text"].str ?? "")
        let given = rec?["c"].str ?? ""
        _color = State(initialValue: given.isEmpty ? lsNoteColors[count % lsNoteColors.count].key : given)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Заголовок", text: $title)
                    TextEditor(text: $text).frame(minHeight: 180)
                }
                Section("Цвет") {
                    HStack(spacing: 16) {
                        ForEach(lsNoteColors, id: \.key) { c in
                            Button { color = c.key } label: {
                                Circle().fill(c.color).frame(width: 32, height: 32)
                                    .overlay(Circle().strokeBorder(Color.primary, lineWidth: color == c.key ? 3 : 0).padding(-4))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(c.name)
                        }
                    }
                }
                if rec != nil {
                    Section { Button("Удалить заметку", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(rec == nil ? "Новая заметка" : "Заметка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() }.bold() }
            }
            .confirmationDialog("Удалить заметку?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let rec { store.delete("notes", rec.id) }
                    dismiss()
                }
            }
            .ptoScreen()
        }
    }

    private func save() {
        var out = rec ?? Rec(id: Fmt.uid(), v: .o([:]))
        out.v["title"] = .s(title)
        out.v["text"] = .s(text)
        out.v["c"] = .s(color)
        store.put("notes", out)
        LsHaptic.success()
        dismiss()
    }
}
