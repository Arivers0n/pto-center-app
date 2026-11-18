import SwiftUI

// MARK: - Статические шпаргалки (как CHEATS в вебе)

private enum ClBlock {
    case note(String)
    case bullets([String])
    case steps([String])
    case table(head: [String], rows: [[String]])

    var plain: String {
        switch self {
        case .note(let s): return s
        case .bullets(let a), .steps(let a): return a.joined(separator: " ")
        case .table(let h, let r): return (h + r.flatMap { $0 }).joined(separator: " ")
        }
    }
}

private struct ClCheat {
    let title: String
    let blocks: [ClBlock]
    var searchText: String { ([title] + blocks.map { $0.plain }).joined(separator: " ").replacingOccurrences(of: "**", with: "") }
}

private let clCheats: [ClCheat] = [
    ClCheat(title: "Состав ИД на трубопроводы (чек-лист)", blocks: [
        .note("Примерный перечень. Итоговый состав — по перечню ИД, который утверждает заказчик (ГОСТ Р 70108-2025) и который входит в договор."),
        .steps(["Общий журнал работ и специальный журнал (сварочные работы)", "Журнал входного контроля, акты входного контроля", "Документы качества: паспорта и сертификаты на трубы, фасонные части, арматуру, электроды и проволоку", "Исполнительные схемы (красные схемы) с привязкой к осям и отметкам", "Акты освидетельствования скрытых работ (АОСР) — приказ 344/пр, прил. 3: опоры, закладные, проходки, изоляция до покраски", "Реестр сварных стыков и заключения по контролю (ВИК / УЗК / РК)", "Акт гидростатического (манометрического) испытания — СП 73.13330.2016, прил. В", "Акт промывки (продувки) трубопроводов", "Акт приёмки оборудования после индивидуального испытания — СП 68.13330.2017, п. 6.6", "Реестр исполнительной документации и акт передачи ИД"])
    ]),
    ClCheat(title: "Порядок: от монтажа до закрытия КС", blocks: [
        .steps(["Входной контроль материалов — документы качества, маркировка, журнал", "Монтаж, сварка, нумерация стыков по схеме", "Контроль стыков, заключения в реестр стыков", "Исполнительная схема по факту (красная)", "**Уведомить об освидетельствовании не позднее чем за 3 рабочих дня** (ГОСТ Р 70108-2025)", "АОСР на скрытые работы", "Гидроиспытание — акт (прил. В СП 73)", "Промывка — акт", "Акт приёмки после индивидуального испытания (СП 68, п. 6.6)", "Сверка «Итого по ИД» и объёма в КС-2 (лист «Свод_КС»), затем КС-2 и КС-3"])
    ]),
    ClCheat(title: "Гидроиспытание: что подготовить", blocks: [
        .bullets(["Исполнительная схема испытуемого участка и номера схем для акта", "Манометры с действующей поверкой, заглушки, опрессовочный насос, вода", "Давление и выдержка — **по проекту и СП 73.13330.2016 (разд. 7)**. Для отопления, теплоснабжения и холодоснабжения: 1,5 Рраб, но не менее 0,2 МПа в нижней точке системы (п. 7.3.1)", "Из ваших актов по системе В1.1: прочность 0,625 МПа — 15 мин, герметичность 0,5 МПа — 24 ч, падение давления 0 (значения заданы проектом ВК)", "Приложить схемы; подписи: застройщик/технадзор, генподрядчик, монтажная организация", "Затем промывка и акт приёмки после индивидуального испытания"]),
        .note("Все значения в таблице «Испытания» книги ПТО_АРТЭК.xlsx — акты соберутся автоматически.")
    ]),
    ClCheat(title: "Закрытие КС: проверка перед подписанием", blocks: [
        .bullets(["По каждой позиции есть ИД (АОСР, схемы, акты испытаний)", "Лист «Свод_КС»: разница «ИД − КС» нулевая или объяснима (красное — не закрыто, жёлтое — закрыто больше, чем по ИД)", "Единицы и расценки совпадают с договором; номера позиций по смете и расценок заполнены (КС-2)", "Давальческие материалы отражены в ОДМ, остатки сходятся", "Период, номер и дата акта, договор, подписанты, НДС и удержания указаны верно", "КС-3: «с начала работ» = сумма всех закрытий, «за период» = текущее закрытие"])
    ]),
    ClCheat(title: "Входной контроль материалов", blocks: [
        .bullets(["Паспорт или сертификат относится именно к этой партии (номер партии/плавки совпадает с маркировкой)", "Размеры, марка стали, стандарт совпадают с проектом и заявкой", "Нержавейка: марка в документе (AISI 304 / 316 и т. д.) совпадает с проектом", "Запись в журнале входного контроля, номер накладной, дата", "Результат «не соответствует» — фиксировать и не пускать в монтаж, уведомить поставщика"])
    ]),
    ClCheat(title: "Сварные стыки: что фиксировать", blocks: [
        .bullets(["Номер стыка в схеме (у вас: 191Т3, 235В1, 49В1-1) и номер схемы", "Размер трубы и линия/система", "Клеймо сварщика, дата сварки", "Вид контроля (ВИК, УЗК, РК) и номер заключения; результат — годен / брак", "Брак: фиксировать исправление и повторный контроль"]),
        .note("Реестр стыков — в ПТО-центре («Стыки») и в книге Excel (лист «Стыки»).")
    ]),
    ClCheat(title: "Нержавейка: AISI ↔ марки ГОСТ (ориентировочно)", blocks: [
        .table(head: ["AISI", "Ориентир по ГОСТ 5632-2014"], rows: [["304", "08Х18Н10"], ["304L", "03Х18Н11"], ["316", "08Х17Н13М2"], ["316L", "03Х17Н14М3"], ["321", "08Х18Н10Т"], ["430", "12Х17"]]),
        .note("Соответствие приблизительное. Для документов берите марку, указанную в проекте и сертификате.")
    ]),
    ClCheat(title: "Дюйм → DN → наружный диаметр", blocks: [
        .table(head: ["Дюйм", "DN", "Наружный ⌀, мм (сталь)"], rows: [["½″", "15", "21,3"], ["¾″", "20", "26,9"], ["1″", "25", "33,7"], ["1¼″", "32", "42,4"], ["1½″", "40", "48,3"], ["2″", "50", "60,3"], ["2½″", "65", "76,1"], ["3″", "80", "88,9"], ["4″", "100", "114,3"], ["5″", "125", "139,7"], ["6″", "150", "168,3"], ["8″", "200", "219,1"], ["10″", "250", "273"], ["12″", "300", "323,9"]])
    ]),
    ClCheat(title: "Перевод давления и формулы", blocks: [
        .bullets(["1 МПа = 10,197 кгс/см² ≈ 10 бар", "1 кгс/см² = 0,098 МПа; 1 атм = 0,101 МПа; 1 м вод. ст. = 0,0098 МПа", "Масса 1 м стальной трубы, кг = 0,02466·(D − s)·s (D, s в мм)", "Объём воды в трубе, л/м = π·d²/4 (d — внутренний ⌀ в дм)", "Расход: 1 м³/ч = 0,278 л/с"]),
        .note("Считать быстрее — в «Калькуляторах» и «Сортаменте труб».")
    ]),
    ClCheat(title: "Частые замечания к ИД", blocks: [
        .bullets(["Нет паспортов или сертификатов на материалы, номера партий не совпадают", "Исполнительная схема без привязки к осям и отметкам или не соответствует проекту", "Акты не подписаны всеми представителями, нет приказов о представителях", "Даты не по порядку: АОСР позже последующих работ, акт испытаний раньше монтажа", "Нет уведомления об освидетельствовании (срок — за 3 рабочих дня)", "Расхождение «Итого по ИД» и объёма в КС-2", "Не указаны шифр проекта и номера листов"])
    ])
]

/// Текст с жирным выделением между «**»
private func clRich(_ s: String) -> Text {
    let parts = s.components(separatedBy: "**")
    var out = Text("")
    for (i, p) in parts.enumerated() where !p.isEmpty {
        out = out + (i % 2 == 1 ? Text(p).bold() : Text(p))
    }
    return out
}

// MARK: - Окно правки

private struct ClSnipDraft: Identifiable {
    let id = UUID()
    var rec: Rec? = nil
    var title = ""
    var text = ""

    init() {}
    init(rec: Rec) {
        self.rec = rec
        self.title = rec["t"].str
        self.text = rec["x"].str
    }
}

private struct ClSnipEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ClSnipDraft
    let onSave: (ClSnipDraft) -> Void
    @FocusState private var focus: Bool

    init(draft: ClSnipDraft, onSave: @escaping (ClSnipDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    private var valid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section("Название") {
                    TextField("Например, приглашение на приёмку", text: $draft.title)
                        .focused($focus)
                }
                SwiftUI.Section("Текст") {
                    TextEditor(text: $draft.text).frame(minHeight: 180)
                }
            }
            .navigationTitle(draft.rec == nil ? "Новая шпаргалка" : "Правка шпаргалки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { onSave(draft); dismiss() }.disabled(!valid)
                }
                ClKeyboardDone { focus = false }
            }
            .onAppear { if draft.rec == nil { focus = true } }
        }
    }
}

// MARK: - Экран «Шпаргалки ПТО»

struct CheatView: View {
    @EnvironmentObject private var store: Store
    @State private var query = ""
    @State private var open: Set<String> = []
    @State private var editing: ClSnipDraft?
    @State private var deleting: Rec?
    @State private var toast: String?

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private var cheats: [ClCheat] { clCheats.filter { q.isEmpty || $0.searchText.lowercased().contains(q) } }
    private var snips: [Rec] {
        store.list("snips")
            .filter { q.isEmpty || ($0["t"].str + " " + $0["x"].str).lowercased().contains(q) }
            .sorted { $0["t"].str.localizedCompare($1["t"].str) == .orderedAscending }
    }
    private var deleteShown: Binding<Bool> {
        Binding<Bool>(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if cheats.isEmpty && snips.isEmpty {
                    EmptyNote(title: "Ничего не найдено", text: "Измените запрос поиска")
                }
                ForEach(cheats, id: \.title) { cheatCard($0) }
                snippetsSection
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
            .clColumn()
        }
        .ptoScreen()
        .navigationTitle("Шпаргалки ПТО")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Поиск по шпаргалкам")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = ClSnipDraft() } label: { Label("Новая шпаргалка", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { draft in ClSnipEditor(draft: draft, onSave: save) }
        .confirmationDialog("Удалить шпаргалку?", isPresented: deleteShown, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { confirmDelete() }
            Button("Отмена", role: .cancel) { deleting = nil }
        } message: {
            Text(deleting?["t"].str ?? "")
        }
        .clToast($toast)
    }

    // MARK: Статические шпаргалки

    private func cheatCard(_ c: ClCheat) -> some View {
        let expanded = !q.isEmpty || open.contains(c.title)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if open.contains(c.title) { open.remove(c.title) } else { open.insert(c.title) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.title).font(.headline).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Развёрнуто" : "Свёрнуто")
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(c.blocks.enumerated()), id: \.offset) { _, b in blockView(b) }
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private func blockView(_ b: ClBlock) -> some View {
        switch b {
        case .note(let s):
            Text(s).font(.footnote).foregroundStyle(.secondary)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        clRich(s).font(.subheadline)
                    }
                }
            }
        case .steps(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 24, alignment: .trailing)
                        clRich(s).font(.subheadline)
                    }
                }
            }
        case .table(let head, let rows):
            tableView(head, rows)
        }
    }

    private func tableView(_ head: [String], _ rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
            GridRow {
                ForEach(head.indices, id: \.self) { j in
                    Text(head[j]).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Divider()
            ForEach(rows.indices, id: \.self) { i in
                GridRow {
                    ForEach(rows[i].indices, id: \.self) { j in
                        Text(rows[i][j]).font(.subheadline).monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: Свои шпаргалки (коллекция snips)

    @ViewBuilder private var snippetsSection: some View {
        Text("Мои шпаргалки").font(.title3.bold()).padding(.top, 8)
        if snips.isEmpty && q.isEmpty {
            EmptyNote(title: "Своих шпаргалок пока нет", text: "Нажмите «+», чтобы сохранить готовый текст, например шаблон письма")
        }
        ForEach(snips) { snipCard($0) }
        if !snips.isEmpty {
            Text("Нажмите на карточку, чтобы скопировать текст.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    private func snipCard(_ r: Rec) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                clCopy(r["x"].str)
                toast = "Текст скопирован"
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(r["t"].str).font(.headline).multilineTextAlignment(.leading)
                    Text(r["x"].str).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading).lineLimit(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Скопировать текст")
            Menu {
                Button { editing = ClSnipDraft(rec: r) } label: { Label("Править", systemImage: "pencil") }
                Button(role: .destructive) { deleting = r } label: { Label("Удалить", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Действия со шпаргалкой")
        }
        .padding(.leading, 14).padding(.vertical, 6)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func save(_ d: ClSnipDraft) {
        var rec = d.rec ?? Rec(id: Fmt.uid(), v: .o([:]))
        rec.v["id"] = .s(rec.id)
        rec.v["t"] = .s(d.title.trimmingCharacters(in: .whitespacesAndNewlines))
        rec.v["x"] = .s(d.text.trimmingCharacters(in: .whitespacesAndNewlines))
        withAnimation { store.put("snips", rec) }
        toast = d.rec == nil ? "Шпаргалка добавлена" : "Изменения сохранены"
    }

    private func confirmDelete() {
        guard let r = deleting else { return }
        withAnimation { store.delete("snips", r.id) }
        deleting = nil
    }
}
