import SwiftUI
import UIKit

// MARK: - Данные КС закрытия (лежат внутри записи закрытия, поле ks — как в веб-версии)

struct KsLine: Identifiable, Equatable {
    var id: String
    var sm = ""
    var name = ""
    var code = ""
    var unit = ""
    var qty = ""
    var price = ""
    var schemes: [String] = []
    var extra: [String: JSON] = [:]

    private static let known: Set<String> = ["id", "sm", "name", "code", "unit", "qty", "price", "schemes"]

    init(id: String = Fmt.uid()) { self.id = id }

    init(json: JSON) {
        let o = json.obj
        let raw = o["id"].str
        id = raw.isEmpty ? Fmt.uid() : raw
        sm = o["sm"].str
        name = o["name"].str
        code = o["code"].str
        unit = o["unit"].str
        qty = o["qty"].num.map { KsNum.flatText($0) } ?? ""
        price = o["price"].num.map { KsNum.flatText($0) } ?? ""
        schemes = o["schemes"].arr.map { $0.str }
        extra = o.filter { !KsLine.known.contains($0.key) }
    }

    var qtyValue: Double { KsNum.parse(qty) ?? 0 }
    var priceValue: Double { KsNum.parse(price) ?? 0 }
    var sum: Double { qtyValue * priceValue }

    var json: JSON {
        var o = extra
        o["id"] = JSON.s(id)
        o["sm"] = JSON.s(sm)
        o["name"] = JSON.s(name)
        o["code"] = JSON.s(code)
        o["unit"] = JSON.s(unit)
        o["qty"] = KsNum.parse(qty).map { JSON.n($0) } ?? JSON.s("")
        o["price"] = KsNum.parse(price).map { JSON.n($0) } ?? JSON.s("")
        o["schemes"] = JSON.a(schemes.map { JSON.s($0) })
        return .o(o)
    }
}

struct KsDoc: Equatable {
    var num = ""
    var dateDoc = ""
    var from = ""
    var to = ""
    var vat = "20"
    var lines: [KsLine] = []

    init() {}

    init(closing c: Rec) {
        if let k = c["ks"], !k.obj.isEmpty {
            num = k["num"].str
            dateDoc = k["dateDoc"].str
            from = k["from"].str
            to = k["to"].str
            vat = k["vat"].num.map { KsNum.flatText($0) } ?? "20"
            lines = k["lines"].arr.map { KsLine(json: $0) }
        } else {
            num = c["no"].str
            dateDoc = c["date"].str
            to = c["date"].str
        }
    }

    var total: Double { lines.reduce(0) { $0 + $1.sum } }
    var vatPercent: Double { KsNum.parse(vat) ?? 0 }

    /// Копия записи закрытия с обновлённым блоком ks; остальные поля (в том числе файлы КС веб-версии) не трогаем
    func applied(to c: Rec) -> Rec {
        var r = c
        var k = c["ks"]?.obj ?? [:]
        k["num"] = JSON.s(num)
        k["dateDoc"] = JSON.s(dateDoc)
        k["from"] = JSON.s(from)
        k["to"] = JSON.s(to)
        k["vat"] = JSON.n(vatPercent)
        k["lines"] = JSON.a(lines.map { $0.json })
        r.v["ks"] = JSON.o(k)
        return r
    }
}

/// Стоимость КС-2 по сохранённой записи закрытия
func ksSavedTotal(_ c: Rec) -> Double {
    let lines: [JSON] = (c["ks"]?["lines"]).arr
    return lines.reduce(0) { (acc: Double, l: JSON) -> Double in acc + (l["qty"].num ?? 0) * (l["price"].num ?? 0) }
}

/// Стоимость по прошлым закрытиям этого проекта: с начала работ и с начала года (КС-3)
func ksPreviousTotals(_ closings: [Rec], for c: Rec) -> (all: Double, year: Double) {
    let y = String((c["date"].str.isEmpty ? Fmt.today : c["date"].str).prefix(4))
    let no = c["no"].num ?? 0
    var all = 0.0, year = 0.0
    for x in closings where x.id != c.id && x["shop"].str == c["shop"].str && (x["no"].num ?? 0) < no {
        let t = ksSavedTotal(x)
        all += t
        if String(x["date"].str.prefix(4)) == y { year += t }
    }
    return (all, year)
}

// MARK: - Объёмы из таблиц к схемам

struct KsVolume: Identifiable {
    let id = UUID()
    var name: String
    var unit: String
    var qty: Double
    var schemes: [String]
    var on = true
}

func ksVolumes(_ schemes: [Rec]) -> [KsVolume] {
    var order: [String] = []
    var acc: [String: KsVolume] = [:]
    for s in schemes {
        for t in s["tbl"].arr {
            for sh in t["sheets"].arr {
                collect(sh, schemeID: s.id, order: &order, acc: &acc)
            }
        }
    }
    return order.compactMap { acc[$0] }
}

private func collect(_ sheet: JSON, schemeID: String, order: inout [String], acc: inout [String: KsVolume]) {
    var header: (n: String, q: String?, u: String?)?
    for r in sheet["rows"].arr {
        let cols = r.obj.sorted { ($0.key.count, $0.key) < ($1.key.count, $1.key) }
        guard let h = header else {
            if let n = cols.first(where: { $0.value.str.lowercased().contains("наименован") }) {
                let q = cols.first(where: { $0.value.str.lowercased().contains("кол") })?.key
                let u = cols.first(where: { $0.value.str.lowercased().contains("ед") })?.key
                header = (n.key, q, u)
            }
            continue
        }
        let name = r[h.n].str.trimmingCharacters(in: .whitespaces)
        guard let qk = h.q, !name.isEmpty, let q = r[qk].num else { continue }
        let unit = (h.u.map { r[$0].str } ?? "").trimmingCharacters(in: .whitespaces)
        let key = name.lowercased() + "|" + unit
        if var v = acc[key] {
            v.qty += q
            if !v.schemes.contains(schemeID) { v.schemes.append(schemeID) }
            acc[key] = v
        } else {
            order.append(key)
            acc[key] = KsVolume(name: name, unit: unit, qty: q, schemes: [schemeID])
        }
    }
}

// MARK: - КС-2 и КС-3 закрытия

private struct KsLineRef: Identifiable { let id: String }

struct KSView: View {
    @EnvironmentObject var store: Store
    let closingID: String
    @State private var doc = KsDoc()
    @State private var baseline = KsDoc()
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var linkLine: KsLineRef?
    @State private var showReq = false
    @State private var showVolumes = false
    @State private var notice: String?

    private var closing: Rec? { store.get("closings", closingID) }
    private var closingSchemes: [Rec] { store.list("schemes").filter { $0["closing"].str == closingID } }
    private var req: [String: String] { KsReq.load(store.cfg) }

    private var previousClosing: Rec? {
        guard let c = closing else { return nil }
        let same = store.list("closings").filter { x in
            x.id != c.id && x["shop"].str == c["shop"].str && !(x["ks"]?["lines"].arr ?? []).isEmpty
        }
        return same.max { ($0["no"].num ?? 0) < ($1["no"].num ?? 0) }
    }

    /// Работы из всех закрытий — для подстановки названия, единицы и цены
    private var knownWorks: [KsLine] {
        var seen = Set<String>()
        var out: [KsLine] = []
        for c in store.list("closings") {
            for j in c["ks"]?["lines"].arr ?? [] {
                let l = KsLine(json: j)
                if !l.name.isEmpty && seen.insert(l.name).inserted { out.append(l) }
            }
        }
        return Array(out.prefix(40))
    }

    var body: some View {
        List {
            if closing != nil {
                actSection
                linesSection
                addSection
                totalsSection
                formsSection
            } else {
                EmptyNote(title: "Закрытие не найдено", text: "Вернитесь к списку закрытий.")
            }
        }
        .listStyle(.insetGrouped)
        .ptoScreen()
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: load)
        .onChange(of: doc) { _ in scheduleSave() }
        .onDisappear { commit() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Готово") { hideKeyboard() } }
        }
        .sheet(isPresented: $showReq) { KsReqView() }
        .sheet(item: $linkLine) { ref in
            KsSchemePicker(schemes: closingSchemes, selected: linkBinding(ref.id))
        }
        .sheet(isPresented: $showVolumes) {
            KsVolumePicker(volumes: ksVolumes(closingSchemes.filter { !$0["tbl"].arr.isEmpty })) { picked in
                addVolumes(picked)
            }
        }
        .alert("КС-2", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: { Text(notice ?? "") }
    }

    // MARK: разделы

    private var actSection: some View {
        Section {
            TextField("№ акта", text: $doc.num)
            KsDateRow(title: "Дата составления", text: $doc.dateDoc)
            KsDateRow(title: "Период с", text: $doc.from)
            KsDateRow(title: "Период по", text: $doc.to)
            HStack {
                Text("НДС, %")
                Spacer()
                TextField("20", text: $doc.vat).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            }
            Button { showReq = true } label: {
                Label((req["customer"] ?? "").isEmpty ? "Заполнить реквизиты" : "Изменить реквизиты", systemImage: "building.2")
            }
        } header: {
            Text("Акт")
        } footer: {
            Text("Заказчик, подрядчик, стройка, договор и подписи общие для всех актов.")
        }
    }

    private var linesSection: some View {
        let linked = Set(doc.lines.flatMap { $0.schemes })
        let noLine = closingSchemes.filter { !linked.contains($0.id) }.count
        let noScheme = doc.lines.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.schemes.isEmpty }.count
        return Section {
            if noLine > 0 || noScheme > 0 || (!closingSchemes.isEmpty && noLine == 0) {
                HStack(spacing: 6) {
                    if noLine > 0 { Badge(text: "Схем без строки КС: \(noLine)", color: .orange) }
                    else if !closingSchemes.isEmpty { Badge(text: "Все схемы в КС", color: .green) }
                    if noScheme > 0 { Badge(text: "Строк без схемы: \(noScheme)", color: .orange) }
                }
            }
            ForEach($doc.lines) { $line in
                KsLineEditor(line: $line, number: number(of: line.id), titles: titles(line.schemes), known: knownWorks) {
                    linkLine = KsLineRef(id: line.id)
                }
                .swipeActions {
                    Button(role: .destructive) { remove(line.id) } label: { Label("Удалить", systemImage: "trash") }
                }
            }
            if doc.lines.isEmpty {
                Text("Строк пока нет. Добавьте работу, возьмите список из прошлого закрытия или объёмы из таблиц к схемам.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text("КС-2 · выполненные работы")
        }
    }

    private var addSection: some View {
        Section {
            Button { withAnimation { doc.lines.append(KsLine()) } } label: { Label("Добавить работу", systemImage: "plus.circle.fill") }
            if let p = previousClosing {
                Button { fromPrevious(p) } label: { Label("Работы из закрытия №\(p["no"].str)", systemImage: "doc.on.doc") }
            }
            if closingSchemes.contains(where: { !$0["tbl"].arr.isEmpty }) {
                Button { showVolumes = true } label: { Label("Объёмы из таблиц к схемам", systemImage: "tablecells.badge.ellipsis") }
            }
            Button { pasteFromClipboard() } label: { Label("Вставить из буфера (Excel)", systemImage: "doc.on.clipboard") }
        } footer: {
            Text("Из буфера: столбцы «наименование, ед., количество, цена» через табуляцию — так их копирует Excel.")
        }
    }

    private var totalsSection: some View {
        let tot = doc.total
        let vat = tot * doc.vatPercent / 100
        let prev = closing.map { ksPreviousTotals(store.list("closings"), for: $0) } ?? (all: 0, year: 0)
        return Section {
            totalRow("Итого по КС-2", tot, strong: true)
            if doc.lines.allSatisfy({ $0.priceValue == 0 }) {
                Text("Цены не указаны").font(.caption).foregroundStyle(.secondary)
            }
            totalRow("С начала проведения работ", prev.all + tot)
            totalRow("С начала года", prev.year + tot)
            totalRow("За отчётный период", tot)
            totalRow("НДС \(KsNum.flatText(doc.vatPercent)) %", vat)
            totalRow("Всего с НДС за период", tot + vat, strong: true)
        } header: {
            Text("КС-3 · справка о стоимости")
        } footer: {
            Text("Прошлые периоды считаются по КС-2 закрытий этого проекта с меньшим номером.")
        }
    }

    private func totalRow(_ title: String, _ v: Double, strong: Bool = false) -> some View {
        HStack {
            Text(title).fontWeight(strong ? .semibold : .regular)
            Spacer()
            Text(KsNum.rub(v) + " ₽").fontWeight(strong ? .semibold : .regular).monospacedDigit()
        }
    }

    private var formsSection: some View {
        Section {
            if let c = closing {
                NavigationLink { KsFormView(model: formModel(c, form: 2)) } label: { Label("Форма КС-2", systemImage: "doc.text") }
                NavigationLink { KsFormView(model: formModel(c, form: 3)) } label: { Label("Форма КС-3", systemImage: "doc.plaintext") }
            }
        } header: {
            Text("Печатные формы")
        } footer: {
            Text("Внутри формы: выгрузка в Excel (CSV) и PDF для печати. Файлы КС, добавленные в веб-версии, хранятся на компьютере и здесь не показываются.")
        }
    }

    // MARK: действия

    private func formModel(_ c: Rec, form: Int) -> KsFormModel {
        let full = ksProjectFull(store.cfg, c["shop"].str)
        let r = KsReq.load(store.cfg)
        if form == 2 { return KsForms.ks2(c, doc, r, full: full) }
        return KsForms.ks3(c, doc, r, full: full, prev: ksPreviousTotals(store.list("closings"), for: c))
    }

    private func number(of id: String) -> Int { (doc.lines.firstIndex { $0.id == id } ?? 0) + 1 }

    private func titles(_ ids: [String]) -> [String] {
        ids.compactMap { store.get("schemes", $0)?["title"].str }
    }

    private func remove(_ id: String) {
        withAnimation { doc.lines.removeAll { $0.id == id } }
    }

    private func linkBinding(_ id: String) -> Binding<[String]> {
        Binding(get: { doc.lines.first { $0.id == id }?.schemes ?? [] },
                set: { new in if let i = doc.lines.firstIndex(where: { $0.id == id }) { doc.lines[i].schemes = new } })
    }

    private func fromPrevious(_ p: Rec) {
        let have = Set(doc.lines.map { $0.name })
        var added = 0
        for j in p["ks"]?["lines"].arr ?? [] {
            var l = KsLine(json: j)
            guard !l.name.isEmpty, !have.contains(l.name) else { continue }
            l = KsLine(id: Fmt.uid()).with(sm: l.sm, name: l.name, code: l.code, unit: l.unit, price: l.price)
            doc.lines.append(l)
            added += 1
        }
        notice = added == 0 ? "Все работы из прошлого закрытия уже есть." : "Добавлено работ: \(added). Впишите количество."
    }

    private func addVolumes(_ picked: [KsVolume]) {
        for v in picked {
            var l = KsLine()
            l.name = v.name
            l.unit = v.unit
            l.qty = KsNum.flatText((v.qty * 1000).rounded() / 1000)
            l.schemes = v.schemes
            doc.lines.append(l)
        }
        notice = "Добавлено строк: \(picked.count). Это материалы и длины из таблиц к схемам — наименования можно переписать в работы."
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, text.contains("\t") || text.contains("\n") else {
            notice = "В буфере нет строк из Excel."
            return
        }
        var added = 0
        for row in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let c = row.components(separatedBy: "\t")
            let name = (c.first ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            var l = KsLine()
            l.name = name
            l.unit = c.count > 1 ? c[1].trimmingCharacters(in: .whitespaces) : ""
            if c.count > 2, let q = KsNum.parse(c[2]) { l.qty = KsNum.flatText(q) }
            if c.count > 3, let p = KsNum.parse(c[3]) { l.price = KsNum.flatText(p) }
            doc.lines.append(l)
            added += 1
        }
        notice = added == 0 ? "Не нашёл строк с наименованием." : "Вставлено строк: \(added)."
    }

    // MARK: сохранение (с задержкой, чтобы не писать на сервер каждую букву)

    private func load() {
        guard !loaded, let c = closing else { return }
        let d = KsDoc(closing: c)
        doc = d
        baseline = d
        loaded = true
    }

    private func scheduleSave() {
        guard loaded, doc != baseline else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if !Task.isCancelled { commit() }
        }
    }

    private func commit() {
        saveTask?.cancel()
        guard loaded, doc != baseline, let c = closing else { return }
        let r = doc.applied(to: c)
        if r.v != c.v { store.put("closings", r) }
        baseline = doc
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private extension KsLine {
    func with(sm: String, name: String, code: String, unit: String, price: String) -> KsLine {
        var l = self
        l.sm = sm; l.name = name; l.code = code; l.unit = unit; l.price = price
        return l
    }
}

// MARK: - Строка работ

private struct KsLineEditor: View {
    @Binding var line: KsLine
    let number: Int
    let titles: [String]
    let known: [KsLine]
    let onLink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(number)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit().frame(minWidth: 18, alignment: .leading).padding(.top, 3)
                TextField("Наименование работ", text: $line.name, axis: .vertical).lineLimit(1...5)
                if !known.isEmpty { knownMenu }
            }
            HStack(spacing: 8) {
                TextField("№ по смете", text: $line.sm)
                TextField("Расценка", text: $line.code)
            }
            .font(.subheadline)
            HStack(spacing: 8) {
                TextField("Ед.", text: $line.unit).frame(width: 52)
                TextField("Кол-во", text: $line.qty).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                Text("×").foregroundStyle(.secondary)
                TextField("Цена, ₽", text: $line.price).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
            HStack {
                Button(action: onLink) {
                    Label(titles.isEmpty ? "Привязать схемы" : ksPlural(titles.count, "схема", "схемы", "схем"), systemImage: titles.isEmpty ? "plus.circle" : "square.stack.3d.up")
                        .font(.footnote)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(titles.isEmpty ? Color.orange : Color.pto)
                Spacer()
                Text(line.sum > 0 ? KsNum.rub(line.sum) + " ₽" : "—").font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private var knownMenu: some View {
        Menu {
            ForEach(known) { k in
                Button(k.name) { fill(k) }
            }
        } label: {
            Image(systemName: "text.badge.plus").frame(minWidth: 32, minHeight: 32)
        }
        .accessibilityLabel("Подставить работу из прошлых закрытий")
    }

    private func fill(_ k: KsLine) {
        line.name = k.name
        if line.unit.isEmpty { line.unit = k.unit }
        if line.price.isEmpty { line.price = k.price }
        if line.sm.isEmpty { line.sm = k.sm }
        if line.code.isEmpty { line.code = k.code }
    }
}

// MARK: - Дата-строка: пусто или выбранная дата

struct KsDateRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        if let d = Fmt.date(text) {
            HStack {
                DatePicker(title, selection: Binding(get: { d }, set: { text = Fmt.iso.string(from: $0) }), displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Очистить: \(title)")
            }
        } else {
            HStack {
                Text(title)
                Spacer()
                Button("Указать") { text = Fmt.today }.buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - Выбор схем для строки

private struct KsSchemePicker: View {
    @Environment(\.dismiss) private var dismiss
    let schemes: [Rec]
    @Binding var selected: [String]

    var body: some View {
        NavigationStack {
            List {
                if schemes.isEmpty { EmptyNote(title: "В закрытии нет схем", text: "Сначала добавьте схемы в это закрытие.") }
                ForEach(schemes) { s in
                    Button { toggle(s.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s["title"].str).foregroundStyle(.primary)
                                let sys = s["sys"].arr.map { $0.str }.joined(separator: ", ")
                                if !sys.isEmpty { Text(sys).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if selected.contains(s.id) { Image(systemName: "checkmark").foregroundStyle(Color.pto) }
                        }
                    }
                }
            }
            .navigationTitle("Схемы к строке")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ id: String) {
        if let i = selected.firstIndex(of: id) { selected.remove(at: i) } else { selected.append(id) }
    }
}

// MARK: - Объёмы из таблиц: выбор, что перенести

private struct KsVolumePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State var volumes: [KsVolume]
    let onAdd: ([KsVolume]) -> Void

    init(volumes: [KsVolume], onAdd: @escaping ([KsVolume]) -> Void) {
        _volumes = State(initialValue: volumes)
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            List {
                if volumes.isEmpty {
                    EmptyNote(title: "Подходящих строк нет", text: "В таблицах к схемам не нашлось строк с наименованием и количеством.")
                }
                ForEach($volumes) { $v in
                    Toggle(isOn: $v.on) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.name)
                            Text("\(Fmt.num(v.qty, 3)) \(v.unit) · схем: \(v.schemes.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Объёмы из таблиц")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить в КС-2") { onAdd(volumes.filter { $0.on }); dismiss() }.disabled(!volumes.contains { $0.on })
                }
            }
        }
    }
}

// MARK: - Реквизиты актов

struct KsReqView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var v: [String: String] = [:]

    private func field(_ key: String, _ title: String) -> some View {
        TextField(title, text: Binding(get: { v[key] ?? "" }, set: { v[key] = $0 }), axis: .vertical)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Стороны") {
                    field("investor", "Инвестор (если есть)")
                    field("customer", "Заказчик (генподрядчик): название, адрес, телефон")
                    field("contractor", "Подрядчик (субподрядчик)")
                    field("stroyka", "Стройка")
                    field("object", "Объект (если отличается от стройки)")
                }
                Section("Договор") {
                    field("contractNo", "Договор №")
                    KsDateRow(title: "Дата договора", text: Binding(get: { v["contractDate"] ?? "" }, set: { v["contractDate"] = $0 }))
                }
                Section("Сдал") {
                    field("sdalPost", "Должность")
                    field("sdalName", "ФИО")
                }
                Section("Принял") {
                    field("prinPost", "Должность")
                    field("prinName", "ФИО")
                }
            }
            .navigationTitle("Реквизиты КС")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        var out: [String: String] = [:]
                        for (k, x) in v { out[k] = x.trimmingCharacters(in: .whitespacesAndNewlines) }
                        KsReq.save(store, out)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                }
            }
            .onAppear { if v.isEmpty { v = KsReq.load(store.cfg) } }
        }
    }
}
